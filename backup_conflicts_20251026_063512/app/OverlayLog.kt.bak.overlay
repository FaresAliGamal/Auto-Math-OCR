package com.math.app

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.text.method.ScrollingMovementMethod
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.*

object OverlayLog {
    private var tv: TextView? = null
    private var wm: WindowManager? = null
    private val buf = ArrayDeque<String>()
    private val sdf = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())

    fun show(ctx: Context) {
        if (tv != null) return
        wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        tv = TextView(ctx).apply {
            textSize = 12f
            typeface = Typeface.MONOSPACE
            setPadding(12, 8, 12, 8)
            setBackgroundColor(0xAA000000.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            movementMethod = ScrollingMovementMethod()
            text = "OverlayLog started…\n"
        }
        val type = if (Build.VERSION.SDK_INT >= 26)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = 12; lp.y = 60
        wm?.addView(tv, lp)
        flush()
    }

    fun hide() {
        tv?.let { wm?.removeView(it) }
        tv = null
        wm = null
        buf.clear()
    }

    fun post(msg: String) {
        val line = "${sdf.format(Date())}  $msg"
        if (tv == null) {
            if (buf.size > 200) buf.removeFirst()
            buf.addLast(line)
        } else {
            tv?.append(line + "\n")
            val layout = tv?.layout
            if (layout != null) {
                val scrollAmount = layout.getLineTop(tv!!.lineCount) - tv!!.height
                if (scrollAmount > 0) tv?.scrollTo(0, scrollAmount) else tv?.scrollTo(0, 0)
            }
        }
    }

    private fun flush() { while (buf.isNotEmpty()) tv?.append(buf.removeFirst() + "\n") }
}
