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
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(manualTrigger, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(manualTrigger, filter)

        // جرّب عرض اللوحة لو الإذن متاح
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
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            OverlayLog.post("Window state changed: ${event.className}")
        }
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
            OverlayLog.post("Projection OFF ⚠️")
            Toast.makeText(this, "⚠️ التقاط الشاشة غير مفعّل", Toast.LENGTH_SHORT).show()
            return
        }

        if (!optionalText.isNullOrBlank() && tryTapByNode(optionalText)) {
            OverlayLog.post("Tapped node by text: \"$optionalText\"")
            Toast.makeText(this, "نقر \"$optionalText\" من الشجرة", Toast.LENGTH_SHORT).show()
            return
        }

        val bmp = ScreenGrabber.capture(this)
            ?: run { OverlayLog.post("capture() returned null"); return }

        OcrHelper.recognizeSmart(this, bmp, { payload ->
            val lines = OcrHelper.detectLines(payload.text)
            val choices = OcrHelper.detectNumericChoices(payload.text)

            OverlayLog.post("OCR lines: " + lines.take(3).joinToString(" | ") { it.text })
            OverlayLog.post("Choices: ${choices.map { it.text }}")

            if (!optionalText.isNullOrBlank()) {
                val box = lines.firstOrNull {
                    MathSolver.normalizeDigits(it.text).contains(MathSolver.normalizeDigits(optionalText))
                }?.box
                if (box != null) {
                    val mapped = OcrHelper.mapRectToScreen(box, payload.transform)
                    OverlayLog.post("Click by OCR text @ (${mapped.centerX().toInt()}, ${mapped.centerY().toInt()})")
                    tapCenter(mapped)
                    return@recognizeSmart
                }
            }

            val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }
            val equationRaw = eqLine?.text?.replace("＝","=")?.replace(" ", "")
            if (equationRaw == null) {
                OverlayLog.post("No clear equation")
                Toast.makeText(this, "لا توجد معادلة واضحة", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }
            val result = MathSolver.solveEquation(equationRaw)
            OverlayLog.post("Equation: $equationRaw => $result")

            if (result == null) {
                Toast.makeText(this, "تعذر حل: $equationRaw", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }

            val target = choices.firstOrNull { MathSolver.normalizeDigits(it.text) == result.toString() }
            if (target == null) {
                OverlayLog.post("Answer $result not in choices")
                Toast.makeText(this, "النتيجة $result غير موجودة", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }

            val mapped = OcrHelper.mapRectToScreen(target.box, payload.transform)
            OverlayLog.post("Tap @ (${mapped.centerX().toInt()}, ${mapped.centerY().toInt()}) for $result")
            tapCenter(mapped)
        }, {
            OverlayLog.post("OCR failure: ${it.message}")
            Toast.makeText(this, "فشل OCR", Toast.LENGTH_SHORT).show()
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
