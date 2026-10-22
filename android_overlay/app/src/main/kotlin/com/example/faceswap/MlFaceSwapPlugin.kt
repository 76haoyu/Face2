package com.example.faceswap

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 真实端侧换脸原生模块（Android + ONNX Runtime）。
 *
 * 关键约束：所有耗时操作（模型下载 / ONNX Session 加载 / 人脸检测+识别+换脸）
 * 全部在 [Dispatchers.IO] 后台协程中执行，结果切回主线程回调 Flutter，
 * 避免 MethodChannel 调用阻塞 UI 导致"卡住不动"。
 *
 * 模型不再打包进 APK，改为首次使用从国内镜像下载；下载进度经 [PROGRESS_CHANNEL]
 * 事件通道实时推送给 Flutter 显示进度条。
 */
class MlFaceSwapPlugin private constructor(private val context: Context) : MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.example.faceswap/ml"
        private const val PROGRESS_CHANNEL = "com.example.faceswap/model_progress"
        private const val TAG = "MlFaceSwapPlugin"

        fun registerWith(engine: FlutterEngine, context: Context) {
            val messenger = engine.dartExecutor.binaryMessenger
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(MlFaceSwapPlugin(context))
            EventChannel(messenger, PROGRESS_CHANNEL).setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                    }

                    override fun onCancel(args: Any?) {
                        eventSink = null
                    }
                }
            )
        }

        @Volatile
        private var eventSink: EventChannel.EventSink? = null
    }

    // 专用后台作用域；插件生命周期内持续可用
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val engine by lazy { FaceSwapEngine(context) }
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun emitProgress(percent: Float, stage: String) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to "progress", "percent" to percent, "stage" to stage))
        }
    }

    private fun emitDone() {
        mainHandler.post { eventSink?.success(mapOf("type" to "done")) }
    }

    private fun emitError(msg: String) {
        mainHandler.post { eventSink?.success(mapOf("type" to "error", "message" to msg)) }
    }

    private fun nowIso(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date())

    /** 确保模型已就绪：缺失则先下载（带进度事件），下载仍缺失则报错回调。 */
    private suspend fun ensureModelsReady(result: Result): Boolean {
        if (engine.modelFilesReady()) return true
        emitProgress(0f, "首次使用，正在下载换脸模型（约 750MB，请保持联网）…")
        engine.prepareModels { p, stage -> emitProgress(p, stage) }
        return if (engine.modelFilesReady()) {
            emitProgress(1f, "模型就绪")
            true
        } else {
            withContext(Dispatchers.Main) {
                result.error("MODEL_FAILED", "换脸模型下载不完整，请检查网络后重试。", null)
            }
            emitError("换脸模型下载不完整，请检查网络后重试。")
            false
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        // 耗时方法全部异步执行，onMethodCall 立即返回，不阻塞 Flutter
        when (call.method) {
            "areModelsReady" -> {
                result.success(engine.modelFilesReady())
            }

            "prepareModels" -> {
                scope.launch {
                    try {
                        emitProgress(0f, "正在准备模型…")
                        engine.prepareModels { p, stage -> emitProgress(p, stage) }
                        if (!engine.modelFilesReady()) {
                            emitError("换脸模型下载不完整，请检查网络后重试。")
                            withContext(Dispatchers.Main) {
                                result.error(
                                    "MODEL_FAILED",
                                    "换脸模型下载不完整，请检查网络后重试。",
                                    null
                                )
                            }
                            return@launch
                        }
                        emitDone()
                        withContext(Dispatchers.Main) { result.success(true) }
                    } catch (e: Exception) {
                        Log.e(TAG, "prepareModels failed", e)
                        emitError(e.message ?: "模型下载失败")
                        withContext(Dispatchers.Main) {
                            result.error("DOWNLOAD_ERROR", "模型下载失败：${e.message}", null)
                        }
                    }
                }
            }

            "buildIdentity" -> {
                val photos = call.argument<List<String>>("photos") ?: emptyList()
                scope.launch {
                    try {
                        if (!ensureModelsReady(result)) return@launch
                        val (embedding, repPath) = engine.buildIdentity(photos)
                        val json = JSONObject().apply {
                            put("id", System.currentTimeMillis().toString())
                            put("createdAt", nowIso())
                            put("sourcePhotoPaths", photos)
                            put("representativeFacePath", repPath ?: "")
                            put("embedding", ArrayList(embedding))
                            put("isDemo", false)
                        }.toString()
                        withContext(Dispatchers.Main) { result.success(json) }
                    } catch (e: Exception) {
                        Log.e(TAG, "buildIdentity failed", e)
                        withContext(Dispatchers.Main) {
                            result.error("ENGINE_ERROR",
                                "建立身份失败：${e.message ?: e.javaClass.simpleName}", null)
                        }
                    }
                }
            }

            "swapImage" -> {
                val target = call.argument<String>("target") ?: ""
                val identityJson = call.argument<String>("identity") ?: "{}"
                scope.launch {
                    try {
                        if (!ensureModelsReady(result)) return@launch
                        val embJson = JSONObject(identityJson).optJSONArray("embedding")
                        val embedding = FloatArray(embJson?.length() ?: 0) { i ->
                            embJson!!.getDouble(i).toFloat()
                        }
                        val outPath = engine.swapImage(target, embedding)
                        if (outPath == null) {
                            withContext(Dispatchers.Main) {
                                result.error("NO_FACE", "目标图片中未检测到人脸。", null)
                            }
                            return@launch
                        }
                        withContext(Dispatchers.Main) { result.success(outPath) }
                    } catch (e: Exception) {
                        Log.e(TAG, "swapImage failed", e)
                        withContext(Dispatchers.Main) {
                            result.error("ENGINE_ERROR",
                                "换脸失败：${e.message ?: e.javaClass.simpleName}", null)
                        }
                    }
                }
            }

            "swapVideo" -> {
                // 视频逐帧换脸需 ffmpeg/ MediaCodec 处理，原生已预留接口。
                result.error("NOT_SUPPORTED",
                    "本版本图片换脸已为真实效果；视频逐帧换脸为进阶功能，请见文档。", null)
            }

            else -> result.notImplemented()
        }
    }
}
