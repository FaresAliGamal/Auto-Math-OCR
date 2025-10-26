package com.math.app

import android.graphics.*
import kotlin.math.max
import kotlin.math.min

object TemplateOcr {
    private const val SIZE = 28

    fun normalizeGlyph(src: Bitmap): Bitmap? {
        val w = src.width; val h = src.height
        val argb = IntArray(w*h); src.getPixels(argb, 0, w, 0, 0, w, h)

        var sum = 0L
        for (c in argb) {
            val r = (c ushr 16) and 0xFF
            val g = (c ushr 8) and 0xFF
            val b = c and 0xFF
            val gray = (0.3*r + 0.59*g + 0.11*b).toInt()
            sum += gray
        }
        val mean = (sum / (w*h)).toInt()
        val threshold = (mean - 25).coerceIn(40, 200)

        val bw = IntArray(w*h)
        for (i in bw.indices) {
            val c = argb[i]
            val r = (c ushr 16) and 0xFF
            val g = (c ushr 8) and 0xFF
            val b = c and 0xFF
            val gray = (0.3*r + 0.59*g + 0.11*b).toInt()
            bw[i] = if (gray < threshold) 0xFFFFFFFF.toInt() else 0xFF000000.toInt()
        }

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
        if (maxX < 0 || maxY < 0) return null

        val pad = 2
        minX = max(0, minX - pad); minY = max(0, minY - pad)
        maxX = min(w-1, maxX + pad); maxY = min(h-1, maxY + pad)

        val cw = maxX - minX + 1
        val ch = maxY - minY + 1

        val cropped = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        cropped.setPixels(bw, 0, w, 0, 0, w, h)
        val glyph = Bitmap.createBitmap(cropped, minX, minY, cw, ch)

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

    fun distance(a: Bitmap, b: Bitmap): Double {
        require(a.width==SIZE && a.height==SIZE && b.width==SIZE && b.height==SIZE)
        val wa = a.width; val ha = a.height
        val pa = IntArray(wa*ha); val pb = IntArray(wa*ha)
        a.getPixels(pa, 0, wa, 0, 0, wa, ha)
        b.getPixels(pb, 0, wa, 0, 0, wa, ha)
        var diff = 0
        for (i in pa.indices) {
            val va = (pa[i] and 0x00FFFFFF) != 0
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
