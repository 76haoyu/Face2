package com.example.faceswap

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 真实端侧换脸原生模块（Android + ONNX Runtime Mobile）。
 *
 * 由 MethodChannel(com.example.faceswap/ml) 与 Dart 侧 MlFaceIdentityService / MlFaceSwapService 通信。
 * 真实推理在 [FaceSwapEngine] 中实现（SCRFD 检测 / ArcFace 识别 / inswapper_128 换脸）。
 *
 * 模型文件需在构建期放入 app/src/main/assets/models/（见 .github/workflows/build_apk.yml）。
 * 若模型缺失或推理抛错，方法会回传清晰错误信息而非崩溃，Dart 侧显示为提示。
 */
class MlFaceSwapPlugin private constructor(private val context: Context) : MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.example.faceswap/ml"
        private const val TAG = "MlFaceSwapPlugin"

        fun registerWith(engine: FlutterEngine) {
            val messenger = engine.dartExecutor.binaryMessenger
            MethodChannel(messenger, CHANNEL).setMethodCallHandler(
                MlFaceSwapPlugin(engine.applicationContext)
            )
        }
    }

    private val engine by lazy { FaceSwapEngine(context) }

    private fun nowIso(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date())

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "buildIdentity" -> {
                    val photos = call.argument<List<String>>("photos") ?: emptyList()
                    if (!engine.modelFilesReady()) {
                        result.error("MODEL_NOT_FOUND",
                            "未找到换脸模型文件，请按文档执行云端构建以打包模型。", null)
                        return
                    }
                    val (embedding, repPath) = engine.buildIdentity(photos)
                    result.success(JSONObject().apply {
                        put("id", System.currentTimeMillis().toString())
                        put("createdAt", nowIso())
                        put("sourcePhotoPaths", photos)
                        put("representativeFacePath", repPath ?: "")
                        put("embedding", ArrayList(embedding))
                        put("isDemo", false)
                    }.toString())
                }

                "swapImage" -> {
                    val target = call.argument<String>("target") ?: ""
                    val identityJson = call.argument<String>("identity") ?: "{}"
                    if (!engine.modelFilesReady()) {
                        result.error("MODEL_NOT_FOUND",
                            "未找到换脸模型文件，请按文档执行云端构建以打包模型。", null)
                        return
                    }
                    val embJson = JSONObject(identityJson).optJSONArray("embedding")
                    val embedding = FloatArray(embJson?.length() ?: 0) { i ->
                        embJson!!.getDouble(i).toFloat()
                    }
                    val outPath = engine.swapImage(target, embedding)
                    if (outPath == null) {
                        result.error("NO_FACE", "目标图片中未检测到人脸。", null)
                        return
                    }
                    result.success(outPath)
                }

                "swapVideo" -> {
                    // 视频逐帧换脸需 ffmpeg/ MediaCodec 处理，原生已预留接口。
                    result.error("NOT_SUPPORTED",
                        "本版本图片换脸已为真实效果；视频逐帧换脸为进阶功能，请见文档。", null)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} failed", e)
            result.error("ENGINE_ERROR", "原生引擎执行出错：${e.message}", null)
        }
    }
}
