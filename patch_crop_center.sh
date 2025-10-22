set -euo pipefail

cat > app/src/main/java/com/math/app/ImageUtils.kt <<'KOT'
package com.math.app

import android.graphics.*

object ImageUtils {
    const val SCALE = 2.5f

    /** قصّ الجزء المتوقع لواجهة السؤال (منتصف الشاشة فقط) */
    fun cropBoard(bmp: Bitmap): Bitmap {
        val w = bmp.width
        val h = bmp.height
        val cw = (w * 0.65f).toInt()  // عرض أضيق
        val ch = (h * 0.40f).toInt()  // ارتفاع متوسط
        val left = ((w - cw) / 2f).toInt()
        val top = ((h - ch) / 2.2f).toInt()
        return Bitmap.createBitmap(bmp, left, top, cw, ch)
    }

    /** تكبير الصورة وتحويلها لأسود/أبيض لزيادة دقة قراءة الأرقام */
    fun preprocessForDigits(src: Bitmap): Bitmap {
        val scaled = Bitmap.createBitmap(
            (src.width * SCALE).toInt(),
            (src.height * SCALE).toInt(),
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(scaled)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(src, Matrix().apply { setScale(SCALE, SCALE) }, paint)

        val w = scaled.width
        val h = scaled.height
        val px = IntArray(w * h)
        scaled.getPixels(px, 0, w, 0, 0, w, h)

        for (i in px.indices) {
            val c = px[i]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            val gray = (0.3 * r + 0.59 * g + 0.11 * b).toInt()
            px[i] = if (gray > 130) Color.WHITE else Color.BLACK
        }

        scaled.setPixels(px, 0, w, 0, 0, w, h)
        return scaled
    }

    /** تصحيح النصوص وحذف أي رموز غير الأرقام والعلامات الرياضية */
    fun normalizeDigitLike(s: String): String {
        var t = s
        t = t.replace(Regex("[Zz]"), "2")
        t = t.replace(Regex("[OoQq]"), "0")
        t = t.replace(Regex("[Ss$]"), "5")
        t = t.replace(Regex("[IiLl]"), "1")
        t = t.replace(Regex("[Bb]"), "8")
        t = t.replace(Regex("[Gg]"), "6")
        // نسمح فقط بـ أرقام + العمليات الحسابية
        t = t.replace(Regex("[^0-9+\\-×x*/÷=]"), "")
        return t
    }
}
KOT

echo "==> Rebuilding..."
./gradlew --no-daemon assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
