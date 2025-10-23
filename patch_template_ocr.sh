set -euo pipefail

mkdir -p app/src/main/java/com/math/app

cat > app/src/main/java/com/math/app/DigitTemplates.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.util.Base64
import java.io.ByteArrayOutputStream

object DigitTemplates {
private const val SP = "digit_templates_v1"
private fun key(d: Int) = "d_$d"

fun saveTemplate(ctx: Context, digit: Int, bmp28: Bitmap) {  
    require(digit in 0..9)  
    val baos = ByteArrayOutputStream()  
    bmp28.compress(Bitmap.CompressFormat.PNG, 100, baos)  
    val b64 = Base64.encodeToString(baos.toByteArray(), Base64.DEFAULT)  
    ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)  
        .edit().putString(key(digit), b64).apply()  
}  

fun loadTemplates(ctx: Context): Map<Int, Bitmap> {  
    val sp = ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)  
    val out = mutableMapOf<Int, Bitmap>()  
    for (d in 0..9) {  
        val b64 = sp.getString(key(d), null) ?: continue  
        val bytes = Base64.decode(b64, Base64.DEFAULT)  
        val bmp = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)  
        if (bmp != null) out[d] = bmp  
    }  
    return out  
}

}
KOT

cat > app/src/main/java/com/math/app/TemplateOcr.kt <<'KOT'
package com.math.app

import android.graphics.*
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object TemplateOcr {
private const val SIZE = 28

// تحويل لصورة ثنائية, وقصّ لأصغر صندوق يحوي البيكسلات الداكنة, ثم تغيير الحجم إلى 28x28  
fun normalizeGlyph(src: Bitmap): Bitmap? {  
    val w = src.width; val h = src.height  
    val argb = IntArray(w*h); src.getPixels(argb, 0, w, 0, 0, w, h)  

    // رمادي + Threshold تلقائي (عَتبة = متوسط + انحياز بسيط)  
    var sum = 0L  
    for (c in argb) {  
        val r = (c ushr 16) and 0xFF  
        val g = (c ushr 8) and 0xFF  
        val b = c and 0xFF  
        val gray = (0.3*r + 0.59*g + 0.11*b).toInt()  
        sum += gray  
    }  
    val mean = (sum / (w*h)).toInt()  
    val threshold = (mean - 25).coerceIn(40, 200) // نخليها تميل لاعتبار النص داكن والخلفية فاتحة  

    // B/W (نجعل الداكن أبيض والنقيض أسود ثم نعيد الترتيب عند النهاية)  
    val bw = IntArray(w*h)  
    for (i in bw.indices) {  
        val c = argb[i]  
        val r = (c ushr 16) and 0xFF  
        val g = (c ushr 8) and 0xFF  
        val b = c and 0xFF  
        val gray = (0.3*r + 0.59*g + 0.11*b).toInt()  
        bw[i] = if (gray < threshold) 0xFFFFFFFF.toInt() else 0xFF000000.toInt()  
    }  

    // قصّ لأصغر مستطيل يحتوي الأبيض (الـ glyph) — نتجاهل أي ألوان/حواف  
    var minX = w; var minY = h; var maxX = -1; var maxY = -1  
    for (y in 0 until h) {  
        val off = y*w  
        for (x in 0 until w) {  
            if (bw[off + x] == 0xFFFFFFFF.toInt()) {  
                if (x < minX) minX = x  
                if (y < minY) minY = y  
                if (x > maxX) maxX = x  
                if (y > maxY) maxY = y  
            }  
        }  
    }  
    if (maxX < 0 || maxY < 0) return null // لا يوجد رقم/شكل  

    // أضف هامش صغير  
    val pad = 2  
    minX = max(0, minX - pad); minY = max(0, minY - pad)  
    maxX = min(w-1, maxX + pad); maxY = min(h-1, maxY + pad)  

    val cw = maxX - minX + 1  
    val ch = maxY - minY + 1  
    val cropped = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)  
    cropped.setPixels(bw, 0, w, 0, 0, w, h)  
    val glyph = Bitmap.createBitmap(cropped, minX, minY, cw, ch)  

    // وضع داخل مربع مربع (square) ثم تغيير الحجم إلى 28x28  
    val side = max(cw, ch)  
    val square = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)  
    val canvas = Canvas(square)  
    canvas.drawColor(Color.BLACK)  
    val left = ((side - cw) / 2f)  
    val top  = ((side - ch) / 2f)  
    val paint = Paint(Paint.FILTER_BITMAP_FLAG)  
    canvas.drawBitmap(glyph, left, top, paint)  

    val out = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)  
    val c2 = Canvas(out)  
    c2.drawColor(Color.BLACK)  
    val m = Matrix()  
    val scale = SIZE.toFloat() / side.toFloat()  
    m.setScale(scale, scale)  
    c2.drawBitmap(square, m, paint)  
    return out  
}  

// مسافة XOR مُطبّعة (0..1) — كل ما قلّت كان التطابق أفضل  
fun distance(a: Bitmap, b: Bitmap): Double {  
    require(a.width==SIZE && a.height==SIZE && b.width==SIZE && b.height==SIZE)  
    val wa = a.width; val ha = a.height  
    val pa = IntArray(wa*ha); val pb = IntArray(wa*ha)  
    a.getPixels(pa, 0, wa, 0, 0, wa, ha)  
    b.getPixels(pb, 0, wa, 0, 0, wa, ha)  
    var diff = 0  
    for (i in pa.indices) {  
        val va = (pa[i] and 0x00FFFFFF) != 0 // أبيض؟  
        val vb = (pb[i] and 0x00FFFFFF) != 0  
        if (va != vb) diff++  
    }  
    return diff.toDouble() / pa.size.toDouble()  
}  

data class Match(val digit: Int, val score: Double)  

fun recognizeSingleDigit(src: Bitmap, templates: Map<Int, Bitmap>): Match? {  
    val n = normalizeGlyph(src) ?: return null  
    var best: Match? = null  
    for ((d, t) in templates) {  
        val s = distance(n, t)  
        if (best == null || s < best!!.score) best = Match(d, s)  
    }  
    return best  
}

}
KOT

applypatch=$(cat <<'KOT'
package com.math.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.*
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast

class AutoMathAccessibilityService : AccessibilityService() {

companion object {  
    const val ACTION_TAP_TEXT = "com.math.app.ACTION_TAP_TEXT"  
    const val ACTION_ACC_STATUS = "com.math.app.ACTION_ACC_STATUS"  
    const val ACTION_SAVE_TEMPLATE = "com.math.app.ACTION_SAVE_TEMPLATE" // extras: region(0..4), digit(0..9)  

    fun isEnabled(ctx: Context): Boolean {  
        val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager  
        val list = am.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)  
        val mePkg = ctx.packageName  
        val meCls = AutoMathAccessibilityService::class.java.name  
        for (info in list) {  
            val si = info.resolveInfo?.serviceInfo ?: continue  
            if (si.packageName == mePkg && si.name == meCls) return true  
        }  
        val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false  
        val me = "$mePkg/$meCls"  
        return enabled.split(':').any { it.equals(me, true) }  
    }  
}  

private var lastRun = 0L  
private val COOLDOWN = 900L  

private val manualTrigger = object : BroadcastReceiver() {  
    override fun onReceive(context: Context?, intent: Intent?) {  
        when (intent?.action) {  
            ACTION_TAP_TEXT -> runOnce(intent.getStringExtra("target"))  
            ACTION_SAVE_TEMPLATE -> saveTemplateFromRegion(  
                intent.getIntExtra("region", -1),  
                intent.getIntExtra("digit", -1)  
            )  
        }  
    }  
}  

override fun onServiceConnected() {  
    val filter = IntentFilter().apply {  
        addAction(ACTION_TAP_TEXT)  
        addAction(ACTION_SAVE_TEMPLATE)  
    }  
    if (Build.VERSION.SDK_INT >= 33) registerReceiver(manualTrigger, filter, Context.RECEIVER_NOT_EXPORTED)  
    else @Suppress("DEPRECATION") registerReceiver(manualTrigger, filter)  
    try { OverlayLog.show(this) } catch (_: Exception) {}  
    OverlayLog.post("Service connected ✅")  
    sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", true))  
}  

override fun onDestroy() {  
    super.onDestroy()  
    OverlayLog.post("Service destroyed ❌")  
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

private fun saveTemplateFromRegion(region: Int, digit: Int) {  
    if (region !in 0..4 || digit !in 0..9) {  
        Toast.makeText(this, "Bad region/digit", Toast.LENGTH_SHORT).show(); return  
    }  
    if (!ScreenGrabber.hasProjection()) {  
        Toast.makeText(this, "Enable screen capture first", Toast.LENGTH_SHORT).show(); return  
    }  
    val bmp = ScreenGrabber.capture(this) ?: run { Toast.makeText(this, "No frame", Toast.LENGTH_SHORT).show(); return }  
    val rects = OverlayRegions.getSavedRectsPx(this)  
    if (rects.size != 5) { Toast.makeText(this, "Set regions first", Toast.LENGTH_SHORT).show(); return }  

    val r = rects[region]  
    val L = r.left.toInt().coerceAtLeast(0)  
    val T = r.top.toInt().coerceAtLeast(0)  
    val W = (r.width().toInt()).coerceAtLeast(1).coerceAtMost(bmp.width - L)  
    val H = (r.height().toInt()).coerceAtLeast(1).coerceAtMost(bmp.height - T)  
    val crop = Bitmap.createBitmap(bmp, L, T, W, H)  
    val norm = TemplateOcr.normalizeGlyph(ImageUtils.preprocessForDigits(crop)) ?: run {  
        Toast.makeText(this, "No glyph found", Toast.LENGTH_SHORT).show(); return  
    }  
    DigitTemplates.saveTemplate(this, digit, norm)  
    Toast.makeText(this, "Saved template for $digit from region $region", Toast.LENGTH_SHORT).show()  
}  

private fun runOnce(optionalText: String?) {  
    val now = SystemClock.uptimeMillis()  
    if (now - lastRun < COOLDOWN) return  
    lastRun = now  

    if (!ScreenGrabber.hasProjection()) {  
        OverlayLog.post("Projection OFF ⚠️")  
        Toast.makeText(this, "Enable screen capture", Toast.LENGTH_SHORT).show()  
        return  
    }  

    val bmp = ScreenGrabber.capture(this) ?: run { OverlayLog.post("capture() == null"); return }  

    val rects = OverlayRegions.getSavedRectsPx(this)  
    if (rects.size == 5) {  
        solveUsingRegions(bmp, rects)  
        return  
    }  
    Toast.makeText(this, "Long-press Run to set regions first", Toast.LENGTH_LONG).show()  
}  

private fun solveUsingRegions(full: Bitmap, rects: List<RectF>) {  
    val crops = rects.map { r ->  
        val L = r.left.toInt().coerceAtLeast(0)  
        val T = r.top.toInt().coerceAtLeast(0)  
        val W = (r.width().toInt()).coerceAtLeast(1).coerceAtMost(full.width - L)  
        val H = (r.height().toInt()).coerceAtLeast(1).coerceAtMost(full.height - T)  
        Bitmap.createBitmap(full, L, T, W, H)  
    }  

    val qBmp = ImageUtils.preprocessForDigits(crops[0])  
    OcrRegionsHelper.recognizeBitmap(qBmp, { qText ->  
        val lines = OcrRegionsHelper.allLines(qText)  
        OverlayLog.post("Q lines: $lines")  
        val eqLine = lines.firstOrNull { it.contains(Regex("[+\\-×x*/÷=]")) }  
        if (eqLine.isNullOrBlank()) {  
            Toast.makeText(this, "No clear equation in question region", Toast.LENGTH_SHORT).show()  
            return@recognizeBitmap  
        }  
        val equation = eqLine.replace("＝","=").replace(" ", "")  
        val result = MathSolver.solveEquation(equation)  
        OverlayLog.post("Equation: $equation => $result")  
        if (result == null) {  
            Toast.makeText(this, "Cannot solve: $equation", Toast.LENGTH_SHORT).show()  
            return@recognizeBitmap  
        }  

        val templates = DigitTemplates.loadTemplates(this)  
        val ansTexts = Array(4){""}  
        var readCount = 0  
        fun done() {  
            if (readCount < 4) return  
            OverlayLog.post("Answers OCR (templates first): ${ansTexts.toList()}")  
            val idx = ansTexts.indexOfFirst { it == result.toString() }  
            if (idx < 0) {  
                Toast.makeText(this, "Answer $result not found", Toast.LENGTH_SHORT).show()  
                return  
            }  
            val r = rects[idx+1]  
            tapCenter(RectF(r))  
            Toast.makeText(this, "Tapped answer: $result", Toast.LENGTH_SHORT).show()  
        }  

        for (i in 1..4) {  
            val pre = ImageUtils.preprocessForDigits(crops[i])  

            // 1) جرّب القوالب (لون-لا مبالٍ)  
            var byTemplate: String? = null  
            if (templates.isNotEmpty()) {  
                TemplateOcr.recognizeSingleDigit(pre, templates)?.let { m ->  
                    if (m.score < 0.18) byTemplate = m.digit.toString()  // عتبة معقولة  
                }  
            }  
            if (byTemplate != null) {  
                ansTexts[i-1] = byTemplate; readCount++; done(); continue  
            }  

            // 2) احتياطي: ML Kit  
            OcrRegionsHelper.recognizeBitmap(pre, { t ->  
                val s = OcrRegionsHelper.bestLineDigits(t)  
                ansTexts[i-1] = MathSolver.normalizeDigits(s)  
                readCount++; done()  
            }, {  
                ansTexts[i-1] = ""  
                readCount++; done()  
            })  
        }  
    }, {  
        OverlayLog.post("OCR failure (Q): ${it.message}")  
        Toast.makeText(this, "OCR failed for question", Toast.LENGTH_SHORT).show()  
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

python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/math/app/MainActivity.kt")
s = p.read_text(encoding="utf-8")
if "import androidx.appcompat.app.AlertDialog" not in s:
s = s.replace("import androidx.appcompat.app.AppCompatActivity",
"import androidx.appcompat.app.AppCompatActivity\nimport androidx.appcompat.app.AlertDialog")
inject = """
// Short dialog to save a template from a region
findViewById<Button>(R.id.btnGrant).setOnLongClickListener {
val ctx = this
val edRegion = android.widget.EditText(ctx).apply { hint = "region 0..4 (0=Q)"; inputType = android.text.InputType.TYPE_CLASS_NUMBER }
val edDigit  = android.widget.EditText(ctx).apply { hint = "digit 0..9"; inputType = android.text.InputType.TYPE_CLASS_NUMBER }
val lay = android.widget.LinearLayout(ctx).apply {
orientation = android.widget.LinearLayout.VERTICAL
setPadding(48,24,48,0)
addView(edRegion); addView(edDigit)
}
AlertDialog.Builder(ctx)
.setTitle("Save digit template")
.setView(lay)
.setPositiveButton("Save") { _, _ ->
val r = edRegion.text.toString().toIntOrNull()
val d = edDigit.text.toString().toIntOrNull()
if (r==null || d==null) {
android.widget.Toast.makeText(ctx, "Enter valid numbers", android.widget.Toast.LENGTH_SHORT).show()
} else {
sendBroadcast(android.content.Intent(com.math.app.AutoMathAccessibilityService.ACTION_SAVE_TEMPLATE)
.putExtra("region", r).putExtra("digit", d))
}
}
.setNegativeButton("Cancel", null)
.show()
true
}
"""
if "Save digit template" not in s:
if "btnGrant).setOnClickListener" in s:
s = s.replace("btnGrant).setOnClickListener", "btnGrant).setOnClickListener") + "\n"  # no-op, fallback
if idx != -1:
br = s.find("{", idx)
depth=1; i=br+1
while i < len(s) and depth>0:
if s[i]=='{': depth+=1
elif s[i]=='}': depth-=1
i+=1
body = s[br+1:i-1] + inject
s = s[:br+1]+body+s[i-1:]
p.write_text(s, encoding="utf-8")
print("[+] MainActivity: added long-press on Grant for saving templates")
PY

echo "==> Build debug APK"
./gradlew --no-daemon assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
