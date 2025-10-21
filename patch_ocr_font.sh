set -euo pipefail

cat > app/src/main/java/com/math/app/ImageUtils.kt <<'KOT'
package com.math.app

import android.graphics.*

object ImageUtils {

    /** قصّ منتصف الشاشة حيث اللوحة (نسبة تقريبية قابلة للتعديل) */
    fun cropBoard(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        // اللوحة تقريبا وسط الشاشة: 60% عرض × 55% ارتفاع
        val cw = (w * 0.70f).toInt()
        val ch = (h * 0.55f).toInt()
        val left = ((w - cw) / 2f).toInt().coerceAtLeast(0)
        val top  = ((h * 0.22f)).toInt().coerceAtLeast(0)
        val rw = (left + cw).coerceAtMost(w) - left
        val rh = (top + ch).coerceAtMost(h) - top
        return Bitmap.createBitmap(src, left, top, rw.coerceAtLeast(1), rh.coerceAtLeast(1))
    }

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
        for (ch in s) {
            val d = map[ch] ?: ch
            sb.append(d)
        }
        return sb.toString()
    }
}
KOT

cat > app/src/main/java/com/math/app/OcrHelper.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)

object OcrHelper {
    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    fun recognize(ctx: Context, bitmap: Bitmap,
                  onDone: (Text) -> Unit, onError: (Exception) -> Unit) {
        // قص اللوحة + معالجة/تكبير قبل الـOCR
        val roi = ImageUtils.cropBoard(bitmap)
        val pre = ImageUtils.preprocessForDigits(roi)
        recognizer.process(InputImage.fromBitmap(pre, 0))
            .addOnSuccessListener(onDone)
            .addOnFailureListener(onError)
    }

    fun detectLines(t: Text): List<Detected> =
        t.textBlocks.flatMap { b ->
            b.lines.mapNotNull { line ->
                line.boundingBox?.let {
                    // طبّع الغلطات الشائعة
                    val txt = ImageUtils.normalizeDigitLike(line.text.trim())
                    Detected(txt, RectF(it))
                }
            }
        }

    fun detectNumericChoices(t: Text): List<Detected> =
        detectLines(t).map { d ->
            d.copy(text = MathSolver.normalizeDigits(ImageUtils.normalizeDigitLike(d.text)))
        }.filter { it.text.matches(Regex("^[\\d]+$")) }
}
KOT

cat > app/src/main/java/com/math/app/MathSolver.kt <<'KOT'
package com.math.app

object MathSolver {

    private val arabicDigits = mapOf(
        '٠' to '0','١' to '1','٢' to '2','٣' to '3','٤' to '4',
        '٥' to '5','٦' to '6','٧' to '7','٨' to '8','٩' to '9'
    )
    fun normalizeDigits(s: String): String =
        s.map { arabicDigits[it] ?: it }.joinToString("")

    fun solveEquation(raw: String): Int? {
        val s = ImageUtils.normalizeDigitLike(
            normalizeDigits(raw)
        )
            .replace("\\s+".toRegex(), "")
            .replace('×','*').replace('x','*').replace('·','*').replace('﹢','+').replace('＋','+')
            .replace('÷','/').replace('＝','=')

        // يسمح بأية مسافات ويقبل = اختياريًا
        val m = Regex("^(-?\\d+)\\s*([+\\-*/])\\s*(-?\\d+)\\s*=?$").find(s) ?: return null
        val a = m.groupValues[1].toLong()
        val op = m.groupValues[2][0]
        val b = m.groupValues[3].toLong()
        val r = when (op) {
            '+' -> a + b
            '-' -> a - b
            '*' -> a * b
            '/' -> if (b != 0L && a % b == 0L) a / b else return null
            else -> return null
        }
        return r.toInt()
    }
}
KOT

./gradlew --no-daemon clean assembleDebug
