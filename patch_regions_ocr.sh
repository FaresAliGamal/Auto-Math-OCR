set -euo pipefail

mkdir -p app/src/main/java/com/math/app
cat > app/src/main/java/com/math/app/RegionsPrefs.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.RectF

object RegionsPrefs {
    private const val KEY = "regions_prefs_v1"
    private const val K_COUNT = "count"
    private const val K_ITEM = "item_"

    /** نحفظ قائمة RectF كنِسَب (0..1) من الشاشة */
    fun save(ctx: Context, rects: List<RectF>, screenW: Int, screenH: Int) {
        val sp = ctx.getSharedPreferences(KEY, Context.MODE_PRIVATE).edit()
        sp.putInt(K_COUNT, rects.size)
        rects.forEachIndexed { i, r ->
            val nr = RectF(r.left / screenW, r.top / screenH, r.right / screenW, r.bottom / screenH)
            sp.putString("$K_ITEM$i", "${nr.left},${nr.top},${nr.right},${nr.bottom}")
        }
        sp.apply()
    }

    /** نرجّع كنِسَب (0..1) — التحويل للبكسل بيتم لاحقًا */
    fun load(ctx: Context): List<RectF> {
        val sp = ctx.getSharedPreferences(KEY, Context.MODE_PRIVATE)
        val n = sp.getInt(K_COUNT, 0)
        if (n <= 0) return emptyList()
        return (0 until n).mapNotNull { i ->
            sp.getString("$K_ITEM$i", null)?.split(",")?.mapNotNull { it.toFloatOrNull() }?.let { v ->
                if (v.size == 4) RectF(v[0], v[1], v[2], v[3]) else null
            }
        }
    }
}
KOT

cat > app/src/main/java/com/math/app/OverlayRegions.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.*
import android.os.Build
import android.view.*
import android.widget.Toast

/** لوحة ضبط 5 مناطق: [0]=السؤال، [1..4]=الإجابات */
object OverlayRegions {
    private var wm: WindowManager? = null
    private val views = mutableListOf<RegionView>()
    private var screenW = 0
    private var screenH = 0
    private var showing = false

    fun toggle(context: Context) {
        if (showing) {
            save(context)
            hide()
            Toast.makeText(context, "تم الحفظ وإغلاق ضبط المناطق", Toast.LENGTH_SHORT).show()
        } else {
            show(context)
            Toast.makeText(context, "اسحب/حجّم المستطيلات ثم اضغط مطوّلًا مرة أخرى للحفظ", Toast.LENGTH_LONG).show()
        }
    }

    private fun show(ctx: Context) {
        if (showing) return
        wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        (wm as WindowManager).defaultDisplay.getRealMetrics(dm)
        screenW = dm.widthPixels
        screenH = dm.heightPixels

        val type = if (Build.VERSION.SDK_INT >= 26)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START

        // إطار شفاف واحد يحتوي على 5 RegionView
        val root = object : ViewGroup(ctx) {
            override fun onLayout(p0: Boolean, p1: Int, p2: Int, p3: Int, p4: Int) {
                // كل RegionView يحدد مكانه بنفسه عبر draw بالـ Rect الداخلي
                for (i in 0 until childCount) {
                    getChildAt(i).layout(0, 0, width, height)
                }
            }
        }

        // نحضّر 5 مستطيلات
        val existing = RegionsPrefs.load(ctx)
        val rectsPx: List<RectF> =
            if (existing.size == 5) existing.map { RectF(it.left * screenW, it.top * screenH, it.right * screenW, it.bottom * screenH) }
            else defaultRects()

        views.clear()
        for (i in 0 until 5) {
            val v = RegionView(ctx, i, rectsPx[i], screenW, screenH)
            root.addView(v, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            views.add(v)
        }

        wm?.addView(root, lp)
        showing = true
    }

    private fun defaultRects(): List<RectF> {
        // توزيع افتراضي مناسب لمعظم الألعاب: سؤال في المنتصف أعلى، 4 إجابات صفّين
        val w = screenW.toFloat(); val h = screenH.toFloat()
        val q = RectF(w*0.15f, h*0.30f, w*0.85f, h*0.45f)
        val a1 = RectF(w*0.10f, h*0.55f, w*0.40f, h*0.65f)
        val a2 = RectF(w*0.60f, h*0.55f, w*0.90f, h*0.65f)
        val a3 = RectF(w*0.10f, h*0.70f, w*0.40f, h*0.80f)
        val a4 = RectF(w*0.60f, h*0.70f, w*0.90f, h*0.80f)
        return listOf(q, a1, a2, a3, a4)
    }

    private fun save(ctx: Context) {
        if (!showing) return
        val rects = views.map { RectF(it.rect) }
        RegionsPrefs.save(ctx, rects, screenW, screenH)
    }

    private fun hide() {
        val w = wm ?: return
        val parent = (views.firstOrNull()?.parent as? ViewGroup) ?: return
        try { w.removeView(parent) } catch (_: Exception) {}
        views.clear()
        showing = false
        wm = null
    }

    fun getSavedRectsPx(ctx: Context): List<RectF> {
        val r = RegionsPrefs.load(ctx)
        if (r.size != 5) return emptyList()
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        val sw = dm.widthPixels.toFloat(); val sh = dm.heightPixels.toFloat()
        return r.map { RectF(it.left*sw, it.top*sh, it.right*sw, it.bottom*sh) }
    }

    private class RegionView(
        ctx: Context,
        private val index: Int,
        val rect: RectF,
        private val maxW: Int,
        private val maxH: Int
    ) : View(ctx) {
        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = when(index){0->0x66FFFFFF.toInt() else->0x66FFFF00.toInt()}
            style = Paint.Style.STROKE
            strokeWidth = 5f
        }
        private val fill = Paint().apply { color = 0x2200AAFF }
        private val textP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = 36f; typeface = Typeface.MONOSPACE
        }
        private val handle = Paint().apply { color = Color.WHITE }

        private var mode: Int = 0 // 0:drag 1:resize
        private var lastX=0f; private var lastY=0f
        private val hs = 36f // handle size

        override fun onDraw(c: Canvas) {
            c.drawRect(rect, fill)
            c.drawRect(rect, border)
            c.drawText(if (index==0) "Q" else "A$index", rect.left+8, rect.top+40, textP)
            // Corner handle
            c.drawRect(rect.right-hs, rect.bottom-hs, rect.right, rect.bottom, handle)
        }

        override fun onTouchEvent(e: MotionEvent): Boolean {
            val x = e.rawX; val y = e.rawY
            when(e.actionMasked){
                MotionEvent.ACTION_DOWN -> {
                    lastX = x; lastY = y
                    mode = if (x>rect.right-hs && y>rect.bottom-hs) 1 else 0
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = x-lastX; val dy = y-lastY
                    lastX = x; lastY = y
                    if (mode==0){
                        rect.offset(dx, dy)
                        clamp()
                    } else {
                        rect.right += dx; rect.bottom += dy
                        clamp()
                    }
                    invalidate()
                    return true
                }
            }
            return super.onTouchEvent(e)
        }

        private fun clamp(){
            if (rect.left<0) rect.offset(-rect.left,0f)
            if (rect.top<0) rect.offset(0f,-rect.top)
            if (rect.right>maxW) rect.right = maxW.toFloat()
            if (rect.bottom>maxH) rect.bottom = maxH.toFloat()
            if (rect.width()<80f) rect.right = rect.left+80f
            if (rect.height()<60f) rect.bottom = rect.top+60f
        }
    }
}
KOT

cat > app/src/main/java/com/math/app/OcrRegionsHelper.kt <<'KOT'
package com.math.app

import android.graphics.Bitmap
import android.graphics.RectF
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

object OcrRegionsHelper {
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    fun recognizeBitmap(bmp: Bitmap, onOk:(Text)->Unit, onErr:(Exception)->Unit){
        recognizer.process(InputImage.fromBitmap(bmp,0))
            .addOnSuccessListener(onOk)
            .addOnFailureListener(onErr)
    }

    /** نصّ سطر واحد من داخل الRect (بعد normalizeDigitLike) */
    fun bestLineDigits(t: Text): String {
        val lines = t.textBlocks.flatMap { it.lines }
        val norm = lines.map { ImageUtils.normalizeDigitLike(it.text) }.filter { it.isNotBlank() }
        return norm.maxByOrNull { it.length } ?: ""
    }

    /** يرجع كل النصوص كسطور (منظفة) */
    fun allLines(t: Text): List<String> =
        t.textBlocks.flatMap { it.lines }.map { ImageUtils.normalizeDigitLike(it.text) }
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
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        val filter = IntentFilter(ACTION_TAP_TEXT)
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

    private fun runOnce(optionalText: String?) {
        val now = SystemClock.uptimeMillis()
        if (now - lastRun < COOLDOWN) return
        lastRun = now

        if (!ScreenGrabber.hasProjection()) {
            OverlayLog.post("Projection OFF ⚠️")
            Toast.makeText(this, "فعّل التقاط الشاشة", Toast.LENGTH_SHORT).show()
            return
        }

        val bmp = ScreenGrabber.capture(this) ?: run { OverlayLog.post("capture() == null"); return }

        val rects = OverlayRegions.getSavedRectsPx(this)
        if (rects.size == 5) {
            solveUsingRegions(bmp, rects)
            return
        }

        // لو مفيش مناطق محفوظة نسيب السلوك القديم (تشغيل يدوي بالنص/ OCR عام)
        Toast.makeText(this, "اضغط مطوّلًا على زر التشغيل لضبط المناطق أولًا", Toast.LENGTH_LONG).show()
    }

    private fun solveUsingRegions(full: Bitmap, rects: List<RectF>) {
        // 0: question, 1..4 answers
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
                Toast.makeText(this, "لا توجد معادلة واضحة داخل منطقة السؤال", Toast.LENGTH_SHORT).show()
                return@recognizeBitmap
            }
            val equation = eqLine.replace("＝","=").replace(" ", "")
            val result = MathSolver.solveEquation(equation)
            OverlayLog.post("Equation: $equation => $result")
            if (result == null) {
                Toast.makeText(this, "تعذر حل: $equation", Toast.LENGTH_SHORT).show()
                return@recognizeBitmap
            }

            // اقرأ كل إجابة كأرقام فقط
            val ansTexts = Array(4){""}
            var readCount = 0
            fun done() {
                if (readCount < 4) return
                OverlayLog.post("Answers OCR: ${ansTexts.toList()}")
                val idx = ansTexts.indexOfFirst { it == result.toString() }
                if (idx < 0) {
                    Toast.makeText(this, "النتيجة $result غير موجودة في مناطق الإجابات", Toast.LENGTH_SHORT).show()
                    return
                }
                val r = rects[idx+1]
                val tap = RectF(r)
                tapCenter(tap)
                Toast.makeText(this, "نقرت الإجابة: $result", Toast.LENGTH_SHORT).show()
            }

            for (i in 1..4) {
                val pb = ImageUtils.preprocessForDigits(crops[i])
                OcrRegionsHelper.recognizeBitmap(pb, { t ->
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
            Toast.makeText(this, "فشل قراءة السؤال", Toast.LENGTH_SHORT).show()
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

perl -0777 -pe '
  if (!/setOnLongClickListener\(\s*{\s*OverlayRegions\.toggle/s) {
    s/(findViewById<Button>\(R\.id\.btnRun\)\.setOnClickListener[^\n]*\n\s*\{[^}]*\}\s*\n)/$1\n        // ضغط مطوّل لفتح/إغلاق وضع ضبط المناطق\n        findViewById<Button>(R.id.btnRun).setOnLongClickListener {\n            try { OverlayRegions.toggle(this) } catch (_: Exception) {}\n            true\n        }\n/s;
  }
' -i app/src/main/java/com/math/app/MainActivity.kt

echo "==> Building..."
./gradlew --no-daemon assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
