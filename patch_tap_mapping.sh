set -euo pipefail

applypatch_img=$(cat <<'KOT'
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
KOT
)
echo "$applypatch_img" > app/src/main/java/com/math/app/ImageUtils.kt

applypatch_ocr=$(cat <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)
data class OcrTransform(val originX: Float, val originY: Float, val scaleX: Float, val scaleY: Float)
data class OcrPayload(val text: Text, val transform: OcrTransform)

object OcrHelper {
    private const val TAG = "OcrHelper"
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /** يرجّع Text + Transform علشان نعرف نعمل mapping */
    fun recognizeSmart(ctx: Context, fullBitmap: Bitmap,
                       onDone: (OcrPayload) -> Unit, onError: (Exception) -> Unit) {
        // قص + بروسسنج
        val crop = ImageUtils.cropBoardWithRect(fullBitmap)
        recognizer.process(InputImage.fromBitmap(crop.bitmap, 0))
            .addOnSuccessListener { t1 ->
                val ok1 = hasEquationOrChoices(t1)
                Log.d(TAG, "Cropped OCR: ok=$ok1, blocks=${t1.textBlocks.size}")
                if (ok1) {
                    // الـOCR اشتغل على صورة مكبرة بمقياس crop.scale
                    val tr = OcrTransform(
                        originX = crop.rect.left.toFloat(),
                        originY = crop.rect.top.toFloat(),
                        scaleX  = 1f / crop.scale,
                        scaleY  = 1f / crop.scale
                    )
                    onDone(OcrPayload(t1, tr))
                } else {
                    // جرّب الشاشة كاملة (بنفس بروسسنج التكبير)
                    val fullPre = ImageUtils.preprocessForDigits(fullBitmap)
                    val s = fullPre.width.toFloat() / fullBitmap.width.toFloat()
                    recognizer.process(InputImage.fromBitmap(fullPre, 0))
                        .addOnSuccessListener { t2 ->
                            val tr = OcrTransform(0f, 0f, 1f / s, 1f / s)
                            Log.d(TAG, "Full OCR fallback: blocks=${t2.textBlocks.size}")
                            onDone(OcrPayload(t2, tr))
                        }
                        .addOnFailureListener(onError)
                }
            }
            .addOnFailureListener(onError)
    }

    private fun hasEquationOrChoices(t: Text): Boolean {
        val lines = detectLines(t)
        val eq = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }
        val nums = detectNumericChoices(t)
        return eq != null || nums.isNotEmpty()
    }

    fun detectLines(t: Text): List<Detected> =
        t.textBlocks.flatMap { b ->
            b.lines.mapNotNull { line ->
                line.boundingBox?.let { Detected(ImageUtils.normalizeDigitLike(line.text.trim()), RectF(it)) }
            }
        }

    fun detectNumericChoices(t: Text): List<Detected> =
        detectLines(t).map { d ->
            d.copy(text = MathSolver.normalizeDigits(ImageUtils.normalizeDigitLike(d.text)))
        }.filter { it.text.matches(Regex("^\\d+$")) }

    /** حوّل مستطيل من إحداثيات صورة الـOCR لإحداثيات الشاشة */
    fun mapRectToScreen(r: RectF, tr: OcrTransform): RectF =
        RectF(
            tr.originX + r.left * tr.scaleX,
            tr.originY + r.top * tr.scaleY,
            tr.originX + r.right * tr.scaleX,
            tr.originY + r.bottom * tr.scaleY
        )
}
KOT
)
echo "$applypatch_ocr" > app/src/main/java/com/math/app/OcrHelper.kt

applypatch_svc=$(cat <<'KOT'
package com.math.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast

class AutoMathAccessibilityService : AccessibilityService() {

    companion object {
        const val ACTION_TAP_TEXT = "com.math.app.ACTION_TAP_TEXT"
        const val ACTION_ACC_STATUS = "com.math.app.ACTION_ACC_STATUS"
        private const val TAG = "AutoMathService"

        fun isEnabled(ctx: Context): Boolean {
            val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            val list = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            val myPkg = ctx.packageName
            val myCls = AutoMathAccessibilityService::class.java.name
            for (info in list) {
                val si = info.resolveInfo?.serviceInfo ?: continue
                if (si.packageName == myPkg && si.name == myCls) return true
            }
            val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = "$myPkg/$myCls"
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }
    }

    private var lastRunMs = 0L
    private val COOL_DOWN = 900L

    private val manualTrigger = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        val filter = IntentFilter(ACTION_TAP_TEXT)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(manualTrigger, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(manualTrigger, filter)
        }
        sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", true))
        Toast.makeText(this, "خدمة الوصول فعّالة ✔️", Toast.LENGTH_SHORT).show()
        Log.d(TAG, "Service connected")
    }

    override fun onDestroy() {
        super.onDestroy()
        sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", false))
        try { unregisterReceiver(manualTrigger) } catch (_: Exception) {}
    }

    override fun onInterrupt() {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            runOnce(null)
        }
    }

    private fun runOnce(optionalText: String?) {
        val now = SystemClock.uptimeMillis()
        if (now - lastRunMs < COOL_DOWN) return
        lastRunMs = now

        if (!ScreenGrabber.hasProjection()) {
            Toast.makeText(this, "⚠️ التقاط الشاشة غير مفعّل", Toast.LENGTH_SHORT).show()
            Log.w(TAG, "Projection OFF")
            return
        }

        if (!optionalText.isNullOrBlank() && tryTapByNode(optionalText)) {
            Toast.makeText(this, "نقر \"$optionalText\" من الشجرة", Toast.LENGTH_SHORT).show()
            Log.d(TAG, "Tapped node by text: $optionalText")
            return
        }

        val bmp = ScreenGrabber.capture(this) ?: run {
            Toast.makeText(this, "لم أستطع التقاط لقطة شاشة", Toast.LENGTH_SHORT).show()
            Log.w(TAG, "capture() returned null")
            return
        }

        OcrHelper.recognizeSmart(this, bmp, { payload ->
            val text = payload.text
            val tr = payload.transform

            val lines = OcrHelper.detectLines(text)
            val choices = OcrHelper.detectNumericChoices(text)

            // ديبَج مفيد
            val sample = lines.take(3).joinToString(" | ") { it.text }
            if (sample.isNotBlank()) Toast.makeText(this, "OCR: $sample", Toast.LENGTH_SHORT).show()
            Toast.makeText(this, "Choices: ${choices.map{it.text}}", Toast.LENGTH_SHORT).show()

            if (!optionalText.isNullOrBlank()) {
                val box = lines.firstOrNull {
                    MathSolver.normalizeDigits(it.text).contains(MathSolver.normalizeDigits(optionalText))
                }?.box
                if (box != null) {
                    val mapped = OcrHelper.mapRectToScreen(box, tr)
                    tapCenter(mapped)
                    Toast.makeText(this, "OCR Tap \"$optionalText\"", Toast.LENGTH_SHORT).show()
                    return@recognizeSmart
                }
            }

            val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }
            val equationRaw = eqLine?.text?.replace("＝","=")?.replace(" ", "")
            if (equationRaw == null) {
                Toast.makeText(this, "لا توجد معادلة واضحة", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }

            val result = MathSolver.solveEquation(equationRaw)
            if (result == null) {
                Toast.makeText(this, "تعذر حل: $equationRaw", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            } else {
                Toast.makeText(this, "معادلة: $equationRaw = $result", Toast.LENGTH_SHORT).show()
            }

            val target = choices.firstOrNull { MathSolver.normalizeDigits(it.text) == result.toString() }
            if (target == null) {
                Toast.makeText(this, "النتيجة $result غير موجودة", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }

            val mapped = OcrHelper.mapRectToScreen(target.box, tr)
            tapCenter(mapped)
            Toast.makeText(this, "نقرت: $result", Toast.LENGTH_SHORT).show()

        }, {
            Toast.makeText(this, "فشل OCR", Toast.LENGTH_SHORT).show()
            Log.e(TAG, "OCR failure", it)
        })
    }

    private fun tapCenter(r: RectF) {
        val cx = (r.left + r.right) / 2f
        val cy = (r.top + r.bottom) / 2f
        val path = Path().apply { moveTo(cx, cy) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 90)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun tryTapByNode(query: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(query)
        for (n in nodes) if (tapNode(n)) return true
        return false
    }
    private fun tapNode(node: AccessibilityNodeInfo?): Boolean {
        var cur = node
        while (cur != null) {
            if (cur.isClickable) return cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            cur = cur.parent
        }
        return false
    }
}
KOT
)
echo "$applypatch_svc" > app/src/main/java/com/math/app/AutoMathAccessibilityService.kt

echo "==> Building..."
./gradlew --no-daemon clean assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
