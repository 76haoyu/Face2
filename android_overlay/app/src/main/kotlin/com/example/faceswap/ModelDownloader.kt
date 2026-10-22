package com.example.faceswap

import android.content.Context
import android.util.Log
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/**
 * 首次使用时把 3 个换脸模型下载到应用私有目录（filesDir/models）。
 *
 * 镜像选择（优先国内可访问）：
 *   - HuggingFace 资源走 hf-mirror.com 镜像
 *   - GitHub 资源走 ghproxy.net 代理
 * 下载带 3 次重试与断点友好的进度回调；w600k_r50 从 buffalo_l.zip 内解压。
 */
class ModelDownloader(private val context: Context) {

    private val tag = "ModelDownloader"
    val modelsDir by lazy { File(context.filesDir, "models").also { it.mkdirs() } }

    private val YUNET_URL =
        "https://ghproxy.net/https://github.com/opencv/opencv_zoo/raw/refs/heads/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
    private val INSWAPPER_URL =
        "https://hf-mirror.com/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx"
    private val BUFFALO_URL =
        "https://ghproxy.net/https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip"

    /** 下载全部 3 个模型；[onProgress] 回调 percent(0~1) 与 stage 文本。仅下载一次。 */
    fun downloadAll(onProgress: (Float, String) -> Unit) {
        val targets = listOf(
            Triple("yunet.onnx", YUNET_URL, "正在下载人脸检测器 (1/3)"),
            Triple("inswapper_128.onnx", INSWAPPER_URL, "正在下载换脸模型 (2/3)"),
            Triple("w600k_r50.onnx", BUFFALO_URL, "正在下载人脸识别模型 (3/3)"),
        )
        val total = targets.size
        targets.forEachIndexed { idx, (name, url, stage) ->
            val local = File(modelsDir, name)
            // w600k_r50 由 zip 解压得到，不在此判断"已存在"
            if (name != "w600k_r50.onnx" && local.exists() && local.length() > 0) {
                onProgress((idx + 1) / total.toFloat(), "$stage（已存在，跳过）")
                return@forEachIndexed
            }
            Log.i(tag, "Downloading $name <- $url")
            if (name == "w600k_r50.onnx") {
                val zip = File(modelsDir, "buffalo_l.zip")
                try {
                    downloadFile(url, zip, stage) { p ->
                        val frac = if (p < 0f) 0.9f else p * 0.9f
                        onProgress((idx + frac) / total.toFloat(), stage)
                    }
                    unzipEntry(zip, "w600k_r50.onnx", local)
                } finally {
                    if (zip.exists()) zip.delete()
                }
            } else {
                downloadFile(url, local, stage) { p ->
                    val frac = if (p < 0f) 0.5f else p
                    onProgress((idx + frac) / total.toFloat(), stage)
                }
            }
            onProgress((idx + 1) / total.toFloat(), "$stage（完成）")
        }
    }

    private fun downloadFile(urlStr: String, out: File, stage: String, onPart: (Float) -> Unit) {
        var attempt = 0
        while (true) {
            attempt++
            var conn: HttpURLConnection? = null
            try {
                val url = URL(urlStr)
                conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 60000
                conn.instanceFollowRedirects = true
                val code = conn.responseCode
                if (code != HttpURLConnection.HTTP_OK) {
                    throw Exception("HTTP $code")
                }
                val totalBytes = conn.contentLength.toLong().coerceAtLeast(0)
                val known = totalBytes > 0
                val tmp = File(out.absolutePath + ".part")
                BufferedInputStream(conn.inputStream).use { bis ->
                    FileOutputStream(tmp).use { fos ->
                        val buf = ByteArray(64 * 1024)
                        var read: Int
                        var done: Long = 0
                        while (bis.read(buf).also { read = it } != -1) {
                            fos.write(buf, 0, read)
                            done += read
                            val p = if (known) (done.toFloat() / totalBytes).coerceIn(0f, 1f) else -1f
                            onPart(p)
                        }
                    }
                }
                if (tmp.length() < 1024) throw Exception("下载内容过小，可能失败")
                if (out.exists()) out.delete()
                tmp.renameTo(out)
                return
            } catch (e: Exception) {
                Log.w(tag, "$stage 第 $attempt 次失败: ${e.message}")
                if (attempt >= 3) throw e
                Thread.sleep(1500)
            } finally {
                conn?.disconnect()
            }
        }
    }

    private fun unzipEntry(zip: File, entryName: String, out: File) {
        ZipInputStream(zip.inputStream()).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (entry.name.endsWith(entryName)) {
                    FileOutputStream(out).use { fos ->
                        val buf = ByteArray(64 * 1024)
                        var read: Int
                        while (zis.read(buf).also { read = it } != -1) fos.write(buf, 0, read)
                    }
                    if (out.length() < 1024) throw Exception("$entryName 解压内容过小")
                    return
                }
                entry = zis.nextEntry
            }
        }
        throw Exception("zip 中未找到 $entryName")
    }
}
