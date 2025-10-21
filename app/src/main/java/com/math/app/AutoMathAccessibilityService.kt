package com.math.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import kotlinx.coroutines.*

class AutoMathAccessibilityService : AccessibilityService() {

    companion object {
        private var instance: AutoMathAccessibilityService? = null
        private var pendingProjection: Pair<Int, Intent>? = null

        fun handoverProjection(resultCode: Int, data: Intent) {
            instance?.let {
                ScreenGrabber.init(it, resultCode, data)
            } ?: run {
                pendingProjection = resultCode to data
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        pendingProjection?.let { (rc, intent) ->
            ScreenGrabber.init(this, rc, intent)
            pendingProjection = null
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    fun clickByText(query: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(query) ?: return false
        for (n in nodes) {
            var cur: AccessibilityNodeInfo? = n
            while (cur != null && !cur.isClickable) cur = cur.parent
            if (cur != null) {
                val ok = cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                if (ok) return true
            }
        }
        return false
    }

    fun tapRect(r: Rect): Boolean {
        val p = Path().apply { moveTo(r.exactCenterX(), r.exactCenterY()) }
        val stroke = GestureDescription.StrokeDescription(p, 0, 60)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    suspend fun solveAndTap(solutionText: String) {
        if (clickByText(solutionText)) return
        val ocrList = OcrHelper.ocrOnScreen(this)
        val rect = OcrHelper.pickBestMatch(ocrList, solutionText)
        if (rect != null) tapRect(rect)
    }
}
