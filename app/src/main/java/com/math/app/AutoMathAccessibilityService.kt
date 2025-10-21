package com.math.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.graphics.RectF
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AutoMathAccessibilityService : AccessibilityService() {

    companion object {
        const val ACTION_TAP_TEXT = "com.math.app.ACTION_TAP_TEXT"
    }

    private var lastRunMs = 0L
    private val COOL_DOWN = 700L

    private val manualTrigger = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        registerReceiver(manualTrigger, IntentFilter(ACTION_TAP_TEXT))
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

        if (!optionalText.isNullOrBlank() && tryTapByNode(optionalText)) return

        val bmp = ScreenGrabber.capture(this) ?: return
        OcrHelper.recognize(this, bmp, { text ->
            if (!optionalText.isNullOrBlank()) {
                val t = OcrHelper.detectLines(text).firstOrNull {
                    MathSolver.normalizeDigits(it.text).contains(
                        MathSolver.normalizeDigits(optionalText)
                    )
                }?.box
                if (t != null) { tapCenter(t); return@recognize }
            }

            val lines = OcrHelper.detectLines(text)
            val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) } ?: return@recognize
            val equationRaw = eqLine.text.replace("＝","=").replace(" ", "")
            val result = MathSolver.solveEquation(equationRaw) ?: return@recognize

            val choices = OcrHelper.detectNumericChoices(text)
            val target = choices.firstOrNull {
                MathSolver.normalizeDigits(it.text) == result.toString()
            } ?: return@recognize

            tapCenter(target.box)
        }, { /* ignore */ })
    }

    private fun tapCenter(r: RectF) {
        val cx = (r.left + r.right) / 2f
        val cy = (r.top + r.bottom) / 2f
        val path = Path().apply { moveTo(cx, cy) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 60)
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
