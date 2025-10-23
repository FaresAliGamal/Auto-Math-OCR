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
            Toast.makeText(this, "Enable screen capture", Toast.LENGTH_SHORT).show()
            return
        }

        val bmp = ScreenGrabber.capture(this) ?: run { OverlayLog.post("capture() == null"); return }

        val rects = OverlayRegions.getSavedRectsPx(this)
        if (rects.size == 5) {
            solveUsingRegions(bmp, rects)
            return
        }

        Toast.makeText(this, "Long-press the Run button to set regions first", Toast.LENGTH_LONG).show()
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

            val ansTexts = Array(4){""}
            var readCount = 0
            fun done() {
                if (readCount < 4) return
                OverlayLog.post("Answers OCR: ${ansTexts.toList()}")
                val idx = ansTexts.indexOfFirst { it == result.toString() }
                if (idx < 0) {
                    Toast.makeText(this, "Answer $result not found in answer regions", Toast.LENGTH_SHORT).show()
                    return
                }
                val r = rects[idx+1]
                val tap = RectF(r)
                tapCenter(tap)
                Toast.makeText(this, "Tapped answer: $result", Toast.LENGTH_SHORT).show()
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
