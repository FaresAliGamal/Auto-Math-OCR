package com.math.app

import android.graphics.*

object ImageUtils {

    data class CropResult(val bitmap: Bitmap, val rect: Rect, val scale: Float)

    /** قصّ منتصف الشاشة حيث اللوحة (نسب قابلة للتعديل) */
    fun cropBoardWithRect(src: Bitmap): CropResult {
        val w = src.width
        val h = src.height
        val cw = (w * 0.70f).toInt()
        val ch = (h * 0.55f).toInt()
        val left = ((w - cw) / 2f).toInt().coerceAtLeast(0)
        val top  = ((h * 0.22f)).toInt().coerceAtLeast(0)
        val rw = (left + cw).coerceAtMost(w) - left
        val rh = (top + ch).coerceAtMost(h) - top
        val roi = Bitmap.createBitmap(src, left, top, rw.coerceAtLeast(1), rh.coerceAtLeast(1))
        // نفس البروسسنج القديم لكن هنطلع كمان معامل التكبير
        val pre = preprocessForDigits(roi)
        val scale = pre.width.toFloat() / roi.width.toFloat()  // تقريبًا 2.5
        return CropResult(pre, Rect(left, top, left + rw, top + rh), scale)
    }

    /** النسخة القديمة لازالت متاحة لو محتاجينها */
    fun cropBoard(src: Bitmap): Bitmap = cropBoardWithRect(src).bitmap

    /** رمادي + رفع تباين + Threshold + تكبير */
    fun preprocessForDigits(src: Bitmap): Bitmap {
        val gray = toGray(src)
        val boosted = boostContrast(gray, 1.6f, -30f)
        val bin = threshold(boosted, 130)
        val scaled = Bitmap.createScaledBitmap(bin, (bin.width * 2.5f).toInt(), (bin.height * 2.5f).toInt(), true)
        return scaled
    }

    private fun toGray(src: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint()
        val cm = ColorMatrix()
        cm.setSaturation(0f)
        paint.colorFilter = ColorMatrixColorFilter(cm)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return out
    }

    private fun boostContrast(src: Bitmap, contrast: Float, brightness: Float): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint()
        val c = contrast
        val b = brightness
        val cm = ColorMatrix(floatArrayOf(
            c, 0f,0f,0f, b,
            0f, c,0f,0f, b,
            0f, 0f,c,0f, b,
            0f, 0f,0f,1f, 0f
        ))
        paint.colorFilter = ColorMatrixColorFilter(cm)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return out
    }

    /** Threshold بسيط (سريع) */
    private fun threshold(src: Bitmap, t: Int): Bitmap {
        val w = src.width; val h = src.height
        val out = src.copy(Bitmap.Config.ARGB_8888, true)
        val pixels = IntArray(w*h)
        out.getPixels(pixels, 0, w, 0, 0, w, h)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            val y = (0.299*r + 0.587*g + 0.114*b).toInt()
            val v = if (y >= t) 255 else 0
            pixels[i] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
        }
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
    }

    /** تحويل أخطاء قراءة شائعة لأرقام */
    fun normalizeDigitLike(s: String): String {
        val map = mapOf(
            'O' to '0', 'o' to '0',
            'I' to '1', 'l' to '1', '|' to '1',
            'Z' to '2',
            'S' to '5',
            'B' to '8',
            'g' to '9'
        )
        val sb = StringBuilder()
        for (ch in s) sb.append(map[ch] ?: ch)
        return sb.toString()
    }
}
