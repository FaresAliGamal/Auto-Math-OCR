package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import java.io.ByteArrayOutputStream

object DigitTemplates {
    private const val SP = "digit_templates_v1"
    private fun keyDigit(d: Int) = "d_$d"
    private fun keyOp(op: String) = "op_$op" // ops: +,-,×,÷

    // ===== Digits 0..9 =====
    fun saveDigit(ctx: Context, digit: Int, bmp28: Bitmap) {
        require(digit in 0..9)
        val b64 = bmp28.toB64()
        ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
            .edit().putString(keyDigit(digit), b64).apply()
    }
    fun loadDigits(ctx: Context): Map<Int, Bitmap> {
        val sp = ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
        val out = mutableMapOf<Int, Bitmap>()
        for (d in 0..9) {
            val b64 = sp.getString(keyDigit(d), null) ?: continue
            fromB64(b64)?.let { bmp -> out[d] = bmp }
        }
        return out
    }

    // ===== Operators (+ - × ÷) =====
    fun saveOp(ctx: Context, op: String, bmp28: Bitmap) {
        require(op in listOf("+","-","×","÷"))
        val b64 = bmp28.toB64()
        ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
            .edit().putString(keyOp(op), b64).apply()
    }
    fun loadOps(ctx: Context): Map<String, Bitmap> {
        val sp = ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
        val out = mutableMapOf<String, Bitmap>()
        for (op in listOf("+","-","×","÷")) {
            val b64 = sp.getString(keyOp(op), null) ?: continue
            fromB64(b64)?.let { bmp -> out[op] = bmp }
        }
        return out
    }

    // ===== Bulk import from gallery URIs =====
    // File name mapping (case-insensitive):
    //   - Digits: starts with 0..9  (e.g., 0.png, 1_foo.png)
    //   - Ops: plus/+ , minus/- , times/x/mul/*/× , divide/div/÷// 
    fun importMany(ctx: Context, uris: List<Uri>): Pair<Int,Int> {
        var ok = 0; var fail = 0
        for (u in uris) {
            val name = (getDisplayName(ctx, u) ?: "").lowercase()

            val bmp = try {
                ctx.contentResolver.openInputStream(u)?.use { ins ->
                    BitmapFactory.decodeStream(ins)
                }
            } catch (_: Exception) { null }
            if (bmp == null) { fail++; continue }

            val norm = TemplateOcr.normalizeGlyph(bmp)
            if (norm == null) { fail++; continue }

            val mappedDigit = name.firstOrNull()?.digitToIntOrNull()
            if (mappedDigit != null) {
                saveDigit(ctx, mappedDigit, norm); ok++; continue
            }

            val op = when {
                name == "+" || name.contains("plus") -> "+"
                name == "-" || name.contains("minus") -> "-"
                name == "*" || name.contains("×") || name.contains("times") || name.contains("mul") || name.contains("x") || name.contains("asterisk") -> "×"
                name == "/" || name.contains("÷") || name.contains("div") || name.contains("divide") -> "÷"
                else -> null
            }
            if (op != null) {
                saveOp(ctx, op, norm); ok++
            } else {
                fail++
            }
        }
        return ok to fail
    }

    // ===== Helpers =====
    private fun Bitmap.toB64(): String {
        val baos = ByteArrayOutputStream()
        this.compress(Bitmap.CompressFormat.PNG, 100, baos)
        return Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
    }

    private fun fromB64(b64: String): Bitmap? {
        return try {
            val bytes = Base64.decode(b64, Base64.NO_WRAP)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (_: Exception) { null }
    }

    private fun getDisplayName(ctx: Context, uri: Uri): String? {
        val c = ctx.contentResolver.query(uri, null, null, null, null) ?: return uri.lastPathSegment
        c.use {
            val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            return if (it.moveToFirst() && idx >= 0) it.getString(idx) else uri.lastPathSegment
        }
    }
}
