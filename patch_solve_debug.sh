set -euo pipefail

cat > app/src/main/java/com/math/app/ScreenGrabber.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager

object ScreenGrabber {
private const val TAG = "ScreenGrabber"
private var mediaProjection: MediaProjection? = null
private var imageReader: ImageReader? = null
private var virtualDisplay: VirtualDisplay? = null
private var firstFrameWaited = false

fun setProjection(mp: MediaProjection) {  
    mediaProjection = mp  
    firstFrameWaited = false  
}  

fun hasProjection(): Boolean = mediaProjection != null  

fun capture(ctx: Context): Bitmap? {  
    val mp = mediaProjection ?: run {  
        Log.w(TAG, "capture(): mediaProjection == null")  
        return null  
    }  
    val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager  
    val dm = DisplayMetrics()  
    @Suppress("DEPRECATION")  
    wm.defaultDisplay.getRealMetrics(dm)  
    val width = dm.widthPixels  
    val height = dm.heightPixels  
    val dpi = dm.densityDpi  

    if (imageReader == null) {  
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)  
        Log.d(TAG, "ImageReader created ${width}x${height}")  
    }  
    if (virtualDisplay == null) {  
        virtualDisplay = mp.createVirtualDisplay(  
            "ocr-vd", width, height, dpi,  
            DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,  
            imageReader!!.surface, null, null  
        )  
        Log.d(TAG, "VirtualDisplay created")  
    }  

    // مهلة أول فريم  
    if (!firstFrameWaited) {  
        try { Thread.sleep(250) } catch (_: InterruptedException) {}  
        firstFrameWaited = true  
    }  

    val img = imageReader!!.acquireLatestImage() ?: run {  
        Thread.sleep(120)  
        imageReader!!.acquireLatestImage()  
    } ?: run {  
        Log.w(TAG, "No image frame yet")  
        return null  
    }  

    val plane = img.planes[0]  
    val buf = plane.buffer  
    val pixelStride = plane.pixelStride  
    val rowStride = plane.rowStride  
    val rowPadding = rowStride - pixelStride * width  
    val bmp = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888)  
    bmp.copyPixelsFromBuffer(buf)  
    img.close()  
    return Bitmap.createBitmap(bmp, 0, 0, width, height)  
}

}
KOT

cat > app/src/main/java/com/math/app/OcrHelper.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.util.Log
import android.widget.Toast
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)

object OcrHelper {
private const val TAG = "OcrHelper"
private val recognizer by lazy {
TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
}

/** يحاول أولاً على cropped+preprocess ولو فشل يجرّب الشاشة كاملة */  
fun recognizeSmart(ctx: Context, fullBitmap: Bitmap,  
                   onDone: (Text) -> Unit, onError: (Exception) -> Unit) {  
    val roi = ImageUtils.cropBoard(fullBitmap)  
    val pre = ImageUtils.preprocessForDigits(roi)  

    recognizer.process(InputImage.fromBitmap(pre, 0))  
        .addOnSuccessListener { t1 ->  
            val ok1 = hasEquationOrChoices(t1)  
            Log.d(TAG, "Cropped OCR: ok=$ok1, blocks=${t1.textBlocks.size}")  
            if (ok1) {  
                onDone(t1)  
            } else {  
                // جرّب الشاشة كاملة (بدون قص)، مع نفس الـpreprocess الخفيف  
                val fullPre = ImageUtils.preprocessForDigits(fullBitmap)  
                recognizer.process(InputImage.fromBitmap(fullPre, 0))  
                    .addOnSuccessListener { t2 ->  
                        Log.d(TAG, "Full OCR fallback: blocks=${t2.textBlocks.size}")  
                        onDone(t2)  
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
            line.boundingBox?.let {  
                val txt = ImageUtils.normalizeDigitLike(line.text.trim())  
                Detected(txt, RectF(it))  
            }  
        }  
    }  

fun detectNumericChoices(t: Text): List<Detected> =  
    detectLines(t).map { d ->  
        d.copy(text = MathSolver.normalizeDigits(ImageUtils.normalizeDigitLike(d.text)))  
    }.filter { it.text.matches(Regex("^\\d+$")) }

}
KOT

applypatch=$(cat <<'KOT'
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

    OcrHelper.recognizeSmart(this, bmp, { text ->  
        val lines = OcrHelper.detectLines(text)  

        // ديبَج: أوّل 3 سطور مقرؤة  
        val sample = lines.take(3).joinToString(" | ") { it.text }  
        if (sample.isNotBlank()) Toast.makeText(this, "OCR: $sample", Toast.LENGTH_SHORT).show()  

        if (!optionalText.isNullOrBlank()) {  
            val t = lines.firstOrNull {  
                MathSolver.normalizeDigits(it.text).contains(MathSolver.normalizeDigits(optionalText))  
            }?.box  
            if (t != null) { tapCenter(t); Toast.makeText(this, "OCR Tap \"$optionalText\"", Toast.LENGTH_SHORT).show(); return@recognizeSmart }  
        }  

        val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }  
        val equationRaw = eqLine?.text?.replace("＝","=")?.replace(" ", "")  

        val choices = OcrHelper.detectNumericChoices(text)  
        Toast.makeText(this, "Choices: ${choices.map{it.text}}", Toast.LENGTH_SHORT).show()  

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

        tapCenter(target.box)  
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
echo "$applypatch" > app/src/main/java/com/math/app/AutoMathAccessibilityService.kt

echo "==> Building..."
./gradlew --no-daemon clean assembleDebug
echo "==> APK ready:"
ls -lh app/build/outputs/apk/debug/
