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
