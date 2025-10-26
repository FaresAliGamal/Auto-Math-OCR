package com.math.app

import android.content.Context
import android.graphics.RectF

object RegionsPrefs {
    private const val KEY = "regions_prefs_v1"
    private const val K_COUNT = "count"
    private const val K_ITEM = "item_"

    fun save(ctx: Context, rects: List<RectF>, screenW: Int, screenH: Int) {
        val sp = ctx.getSharedPreferences(KEY, Context.MODE_PRIVATE).edit()
        sp.putInt(K_COUNT, rects.size)
        rects.forEachIndexed { i, r ->
            val nr = RectF(r.left / screenW, r.top / screenH, r.right / screenW, r.bottom / screenH)
            sp.putString("$K_ITEM$i", "${nr.left},${nr.top},${nr.right},${nr.bottom}")
        }
        sp.apply()
    }

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
