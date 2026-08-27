package com.example.faceswap

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

class FaceSwapEngine(private val context: Context) {

    private val tag = "FaceSwapEngine"
    private val modelsDir by lazy { File(context.filesDir, "models").also { it.mkdirs() } }

    private var env: OrtEnvironment? = null
    private var detSession: OrtSession? = null
    private var recSession: OrtSession? = null
    private var swapSession: OrtSession? = null
    private var assetsCopied = false

    data class Face(val rect: RectF, val landmarks: FloatArray)

    private val REF112 = floatArrayOf(
        38.2946f, 51.6963f,
        73.5318f, 51.6963f,
        56.0252f, 71.7366f,
        41.5493f, 92.3655f,
        70.7299f, 92.3655f
    )

    fun modelFilesReady(): Boolean {
        copyAssetsModelsIfNeeded()
        return listOf("yunet.onnx", "w600k_r50.onnx", "inswapper_128.onnx")
            .all { File(modelsDir, it).exists() && File(modelsDir, it).length() > 0 }
    }

    private fun copyAssetsModelsIfNeeded() {
        if (assetsCopied) return
        assetsCopied = true
        val assetManager = context.assets
        try {
            val models = assetManager.list("models") ?: return
            for (m in models) {
                if (!m.endsWith(".onnx")) continue
                val outFile = File(modelsDir, m)
                if (outFile.exists() && outFile.length() > 0) continue
                Log.i(tag, "Copying asset model: $m")
                assetManager.open("models/$m").use { input ->
                    outFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(tag, "Failed to copy assets models", e)
        }
    }

    @Synchronized
    private fun ensureSessions() {
        if (swapSession != null) return
        env = OrtEnvironment.getEnvironment()
        val opts = OrtSession.SessionOptions()
        detSession = env!!.createSession(File(modelsDir, "yunet.onnx").absolutePath, opts)
        recSession = env!!.createSession(File(modelsDir, "w600k_r50.onnx").absolutePath, opts)
        swapSession = env!!.createSession(File(modelsDir, "inswapper_128.onnx").absolutePath, opts)
    }

    fun buildIdentity(photos: List<String>): Pair<List<Double>, String?> {
        ensureSessions()
        val sum = FloatArray(512)
        var count = 0
        var repPath: String? = null
        for (p in photos) {
            val bmp = BitmapFactory.decodeFile(p) ?: continue
            val face = detectLargest(bmp) ?: continue
            val aligned = align(bmp, face.landmarks, 112f)
            val emb = recognize(aligned) ?: continue
            for (i in emb.indices) sum[i] += emb[i]
            count++
            if (repPath == null) {
                repPath = File(modelsDir, "representative.png").absolutePath
                aligned.compress(Bitmap.CompressFormat.PNG, 100, File(repPath).outputStream())
            }
        }
        if (count == 0) throw IllegalStateException("未在照片中检测到人脸")
        val avg = FloatArray(512) { sum[it] / count }
        normalize(avg)
        return avg.map { it.toDouble() } to repPath
    }

    fun swapImage(targetPath: String, embedding: FloatArray): String? {
        ensureSessions()
        val target = BitmapFactory.decodeFile(targetPath) ?: return null
        val faces = detectAll(target)
        if (faces.isEmpty()) return null

        val base = target.copy(Bitmap.Config.ARGB_8888, true)

        for (face in faces) {
            val aligned = align(target, face.landmarks, 128f) ?: continue
            val swapped = runInswapper(aligned, embedding) ?: continue
            val back = alignBack(swapped, face.landmarks, target.width, target.height)
            val mask = buildFeatherMask(back.width, back.height, face.rect)
            composite(base, back, mask)
        }
        val out = File(modelsDir, "swap_${System.currentTimeMillis()}.png")
        base.compress(Bitmap.CompressFormat.PNG, 100, out.outputStream())
        return out.absolutePath
    }

    private fun preprocessCHW(bmp: Bitmap, size: Int, mean: Float, std: Float, bgr: Boolean): FloatArray {
        val scaled = Bitmap.createScaledBitmap(bmp, size, size, true)
        val pixels = IntArray(size * size)
        scaled.getPixels(pixels, 0, size, 0, 0, size, size)
        val out = FloatArray(3 * size * size)
        var o = 0
        for (i in pixels.indices) {
            val c = pixels[i]
            val r = (Color.red(c) - mean) / std
            val g = (Color.green(c) - mean) / std
            val b = (Color.blue(c) - mean) / std
            val cr = if (bgr) b else r
            val cg = g
            val cb = if (bgr) r else b
            out[o] = cr; o++
        }
        o = size * size
        for (i in pixels.indices) {
            val c = pixels[i]
            val g = (Color.green(c) - mean) / std
            out[o] = g; o++
        }
        o = 2 * size * size
        for (i in pixels.indices) {
            val c = pixels[i]
            val r = (Color.red(c) - mean) / std
            val b = (Color.blue(c) - mean) / std
            val cr = if (bgr) b else r
            val cb = if (bgr) r else b
            out[o] = cb; o++
        }
        return out
    }

    private fun detectAll(bmp: Bitmap): List<Face> {
        val size = 320
        val input = preprocessCHW(bmp, size, 127.5f, 127.5f, bgr = false)
        val shape = longArrayOf(1, 3, size.toLong(), size.toLong())
        val tensor = floatTensor(input, shape)
        val inName = detSession!!.inputNames.iterator().next()
        val res = detSession!!.run(mapOf(inName to tensor))
        val arr = res.get(0).value as Array<*>
        val level1 = arr[0]
        val rows: Array<*> = if (level1 is Array<*> && level1.firstOrNull() is FloatArray) {
            level1 as Array<*>
        } else {
            (level1 as Array<*>)[0] as Array<*>
        }
        val sx = bmp.width.toFloat() / size
        val sy = bmp.height.toFloat() / size
        val faces = mutableListOf<Face>()
        for (r in rows) {
            val row = r as FloatArray
            val score = row[4]
            if (score < 0.6f) continue
            val x = row[0] * sx
            val y = row[1] * sy
            val w = row[2] * sx
            val h = row[3] * sy
            val lm = FloatArray(10)
            for (k in 0 until 5) {
                lm[k * 2] = row[5 + k * 2] * sx
                lm[k * 2 + 1] = row[5 + k * 2 + 1] * sy
            }
            faces.add(Face(RectF(x, y, x + w, y + h), lm))
        }
        res.close()
        return faces
    }

    private fun detectLargest(bmp: Bitmap): Face? {
        return detectAll(bmp).maxByOrNull { (it.rect.width() * it.rect.height()) }
    }

    private fun recognize(aligned112: Bitmap): FloatArray? {
        val input = preprocessCHW(aligned112, 112, 127.5f, 128f, bgr = true)
        val shape = longArrayOf(1, 3, 112, 112)
        val tensor = floatTensor(input, shape)
        val inName = recSession!!.inputNames.iterator().next()
        val res = recSession!!.run(mapOf(inName to tensor))
        val v = res.get(0).value
        val emb = if (v is Array<*> && v[0] is FloatArray) {
            (v[0] as FloatArray).clone()
        } else null
        res.close()
        return emb
    }

    private fun runInswapper(aligned128: Bitmap, embedding: FloatArray): Bitmap? {
        val tInput = preprocessCHW(aligned128, 128, 127.5f, 127.5f, bgr = false)
        val sInput = FloatArray(512) { embedding.getOrElse(it) { 0f } }
        normalize(sInput)
        val tTensor = floatTensor(tInput, longArrayOf(1, 3, 128, 128))
        val sTensor = floatTensor(sInput, longArrayOf(1, 512))
        val names = swapSession!!.inputNames.toList()
        val inputs = mapOf(names[0] to tTensor, names[1] to sTensor)
        val res = swapSession!!.run(inputs)
        val v = res.get(0).value
        val out = v as Array<*>
        val chR = out[0] as Array<*>
        val chG = out[1] as Array<*>
        val chB = out[2] as Array<*>
        val h = chR.size
        val w = (chR[0] as FloatArray).size
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(w * h)
        for (y in 0 until h) {
            val rowR = chR[y] as FloatArray
            val rowG = chG[y] as FloatArray
            val rowB = chB[y] as FloatArray
            for (x in 0 until w) {
                val r = ((rowR[x] + 1f) * 127.5f).toInt().coerceIn(0, 255)
                val g = ((rowG[x] + 1f) * 127.5f).toInt().coerceIn(0, 255)
                val b = ((rowB[x] + 1f) * 127.5f).toInt().coerceIn(0, 255)
                pixels[y * w + x] = Color.rgb(r, g, b)
            }
        }
        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
        res.close()
        return bmp
    }

    private fun align(bmp: Bitmap, landmarks: FloatArray, size: Float): Bitmap {
        val ref = scaleRef(size)
        val m = fitSimilarity(landmarks, ref)
        return warp(bmp, m, size.toInt(), size.toInt())
    }

    private fun alignBack(aligned: Bitmap, landmarks: FloatArray, ow: Int, oh: Int): Bitmap {
        val ref = scaleRef(aligned.width.toFloat())
        val m = fitSimilarity(ref, landmarks)
        return warp(aligned, m, ow, oh)
    }

    private fun scaleRef(size: Float): FloatArray {
        val s = size / 112f
        return FloatArray(10) { REF112[it] * s }
    }

    private fun fitSimilarity(src: FloatArray, dst: FloatArray): DoubleArray {
        var mx = 0f; var my = 0f; var MX = 0f; var MY = 0f
        for (i in 0 until 5) {
            mx += src[i * 2]; my += src[i * 2 + 1]
            MX += dst[i * 2]; MY += dst[i * 2 + 1]
        }
        mx /= 5f; my /= 5f; MX /= 5f; MY /= 5f
        var num = 0f; var den = 0f; var cross = 0f
        for (i in 0 until 5) {
            val xs = src[i * 2] - mx; val ys = src[i * 2 + 1] - my
            val Xs = dst[i * 2] - MX; val Ys = dst[i * 2 + 1] - MY
            num += Xs * xs + Ys * ys
            cross += Ys * xs - Xs * ys
            den += xs * xs + ys * ys
        }
        val a = num / den
        val b = cross / den
        val tx = MX - (a * mx - b * my)
        val ty = MY - (b * mx + a * my)
        return doubleArrayOf(a.toDouble(), (-b).toDouble(), tx.toDouble(), b.toDouble(), a.toDouble(), ty.toDouble())
    }

    private fun warp(src: Bitmap, m: DoubleArray, ow: Int, oh: Int): Bitmap {
        val a = m[0]; val nb = m[1]; val tx = m[2]; val b = m[3]; val c = m[4]; val ty = m[5]
        val det = a * c - nb * b
        val out = Bitmap.createBitmap(ow, oh, Bitmap.Config.ARGB_8888)
        val px = IntArray(ow * oh)
        val sw = src.width; val sh = src.height
        val sp = IntArray(sw * sh)
        src.getPixels(sp, 0, sw, 0, 0, sw, sh)
        for (Y in 0 until oh) {
            for (X in 0 until ow) {
                val x = ((a * (X - tx) + b * (Y - ty)) / det).toFloat()
                val y = ((nb * (X - tx) + c * (Y - ty)) / det).toFloat()
                var sx = x.toInt(); var sy = y.toInt()
                if (sx < 0) sx = 0; if (sy < 0) sy = 0; if (sx >= sw - 1) sx = sw - 2; if (sy >= sh - 1) sy = sh - 2
                var fx = x - sx; if (fx < 0) fx = 0f; var fy = y - sy; if (fy < 0) fy = 0f
                val i = sy * sw + sx
                val p00 = sp[i]; val p10 = sp[i + 1]; val p01 = sp[i + sw]; val p11 = sp[i + sw + 1]
                px[Y * ow + X] = bilinear(p00, p10, p01, p11, fx, fy)
            }
        }
        out.setPixels(px, 0, ow, 0, 0, ow, oh)
        return out
    }

    private fun bilinear(p00: Int, p10: Int, p01: Int, p11: Int, fx: Float, fy: Float): Int {
        val r = lerp(Color.red(p00), Color.red(p10), Color.red(p01), Color.red(p11), fx, fy)
        val g = lerp(Color.green(p00), Color.green(p10), Color.green(p01), Color.green(p11), fx, fy)
        val bl = lerp(Color.blue(p00), Color.blue(p10), Color.blue(p01), Color.blue(p11), fx, fy)
        return Color.rgb(r, g, bl)
    }

    private fun lerp(a: Int, b: Int, c: Int, d: Int, fx: Float, fy: Float): Int {
        val top = a + (b - a) * fx
        val bot = c + (d - c) * fx
        return (top + (bot - top) * fy).toInt().coerceIn(0, 255)
    }

    private fun buildFeatherMask(w: Int, h: Int, rect: RectF): Bitmap {
        val mask = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val cv = Canvas(mask)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.color = Color.WHITE
        val cx = rect.centerX(); val cy = rect.centerY()
        val rx = rect.width() / 2 * 1.05f
        val ry = rect.height() / 2 * 1.05f
        cv.drawOval(cx - rx, cy - ry, cx + rx, cy + ry, p)
        return mask
    }

    private fun composite(base: Bitmap, layer: Bitmap, mask: Bitmap) {
        val w = layer.width; val h = layer.height
        val lp = IntArray(w * h); layer.getPixels(lp, 0, w, 0, 0, w, h)
        val mp = IntArray(w * h); mask.getPixels(mp, 0, w, 0, 0, w, h)
        val cp = IntArray(w * h); base.getPixels(cp, 0, w, 0, 0, w, h)
        for (i in lp.indices) {
            val al = Color.alpha(mp[i])
            if (al == 0) continue
            val fa = al / 255f
            val fb = 1f - fa
            val r = (Color.red(lp[i]) * fa + Color.red(cp[i]) * fb).toInt()
            val g = (Color.green(lp[i]) * fa + Color.green(cp[i]) * fb).toInt()
            val bl = (Color.blue(lp[i]) * fa + Color.blue(cp[i]) * fb).toInt()
            cp[i] = Color.argb(255, r, g, bl)
        }
        base.setPixels(cp, 0, w, 0, 0, w, h)
    }

    private fun normalize(v: FloatArray) {
        var s = 0f
        for (x in v) s += x * x
        s = sqrt(s)
        if (s > 1e-8f) for (i in v.indices) v[i] = v[i] / s
    }

    private fun floatTensor(data: FloatArray, shape: LongArray): OnnxTensor {
        val e = env ?: throw IllegalStateException("engine not initialized")
        val bb = ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder())
        val fb = bb.asFloatBuffer()
        fb.put(data)
        fb.rewind()
        return OnnxTensor.createTensor(e, fb, shape)
    }
}
