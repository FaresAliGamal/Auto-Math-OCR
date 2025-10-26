package com.math.app

import android.content.Context
import android.graphics.*
import android.os.Build
import android.util.DisplayMetrics
import android.view.*
import android.view.ViewGroup
import android.widget.Toast

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
            Toast.makeText(context, "Saved regions and closed editor", Toast.LENGTH_SHORT).show()
        } else {
            show(context)
            Toast.makeText(context, "Drag/resize rectangles, then long-press again to save", Toast.LENGTH_LONG).show()
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

        val root = object : ViewGroup(ctx) {
            override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
                for (i in 0 until childCount) {
                    getChildAt(i).layout(0, 0, width, height)
                }
            }
        }

        val existing = RegionsPrefs.load(ctx)
        val rectsPx: List<RectF> =
            if (existing.size == 5) existing.map { RectF(it.left * screenW, it.top * screenH, it.right * screenW, it.bottom * screenH) }
            else defaultRects()

        views.clear()
        for (i in 0 until 5) {
            val v = RegionView(ctx, i, rectsPx[i], screenW, screenH)
            root.addView(v, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            views.add(v)
        }

        wm?.addView(root, lp)
        showing = true
    }

    private fun defaultRects(): List<RectF> {
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
            color = if (index == 0) 0x66FFFFFF.toInt() else 0x66FFFF00.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 5f
        }
        private val fill = Paint().apply { color = 0x2200AAFF.toInt() }
        private val textP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = 36f; typeface = Typeface.MONOSPACE
        }
        private val handle = Paint().apply { color = Color.WHITE }

        private var mode = 0 // 0: drag, 1: resize
        private var lastX = 0f; private var lastY = 0f
        private val hs = 36f // handle size

        override fun onDraw(c: Canvas) {
            c.drawRect(rect, fill)
            c.drawRect(rect, border)
            c.drawText(if (index == 0) "Q" else "A$index", rect.left + 8, rect.top + 40, textP)
            // corner handle
            c.drawRect(rect.right - hs, rect.bottom - hs, rect.right, rect.bottom, handle)
        }

        override fun onTouchEvent(e: MotionEvent): Boolean {
            val x = e.rawX; val y = e.rawY

            // Only handle touches that start near/inside this rectangle (with small margin for the resize handle)
            if (e.action == MotionEvent.ACTION_DOWN &&
                !RectF(rect.left - hs, rect.top - hs, rect.right + hs, rect.bottom + hs).contains(x, y)
            ) {
                return false
            }

            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = x; lastY = y
                    mode = if (x > rect.right - hs && y > rect.bottom - hs) 1 else 0
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = x - lastX; val dy = y - lastY
                    lastX = x; lastY = y
                    if (mode == 0) {
                        rect.offset(dx, dy)
                    } else {
                        rect.right += dx; rect.bottom += dy
                    }
                    clamp()
                    invalidate()
                    return true
                }
            }
            return super.onTouchEvent(e)
        }

        private fun clamp() {
            if (rect.left < 0) rect.offset(-rect.left, 0f)
            if (rect.top < 0) rect.offset(0f, -rect.top)
            if (rect.right > maxW) rect.right = maxW.toFloat()
            if (rect.bottom > maxH) rect.bottom = maxH.toFloat()
            if (rect.width() < 80f) rect.right = rect.left + 80f
            if (rect.height() < 60f) rect.bottom = rect.top + 60f
        }
    }
}
