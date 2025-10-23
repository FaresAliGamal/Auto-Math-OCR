set -euo pipefail

echo "[1/3] Overwrite DigitTemplates.kt with clean, correct version..."
cat > app/src/main/java/com/math/app/DigitTemplates.kt <<'KOT'
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
KOT

echo "[2/3] Ensure Service uses saveDigit/loadDigits..."
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/math/app/AutoMathAccessibilityService.kt")
if p.exists():
    s = p.read_text(encoding="utf-8")
    s = s.replace("DigitTemplates.saveTemplate(this, digit, norm)", "DigitTemplates.saveDigit(this, digit, norm)")
    s = s.replace("DigitTemplates.loadTemplates(this)", "DigitTemplates.loadDigits(this)")
    p.write_text(s, encoding="utf-8")
    print("[+] Service updated")
else:
    print("[!] Service file not found (skipped)")
PY

echo "[3/3] Clean MainActivity: remove old onActivityResult/REQ_*, add ActivityResult launcher, wire button..."
python3 - <<'PY'
import re
from pathlib import Path

p = Path("app/src/main/java/com/math/app/MainActivity.kt")
s = p.read_text(encoding="utf-8")

s = re.sub(r'\n\s*override\s+fun\s+onActivityResult\([^)]*\)\s*\{.*?\n\}\s*', '\n', s, flags=re.S)

s = re.sub(r'\s*private\s+const\s+val\s+REQ_IMPORT_TEMPLATES\s*=\s*\d+\s*', '', s)

def ensure_import(block, anchor, imp):
    if imp not in block:
        block = block.replace(anchor, anchor + "\n" + imp)
    return block

s = ensure_import(s, "import android.os.Bundle", "import android.widget.Button")
s = ensure_import(s, "import android.os.Bundle", "import android.content.Intent")
s = ensure_import(s, "import android.os.Bundle", "import android.net.Uri")
s = ensure_import(s, "import android.os.Bundle", "import android.widget.Toast")
s = ensure_import(s, "import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AlertDialog")
s = ensure_import(s, "import androidx.appcompat.app.AppCompatActivity", "import androidx.activity.result.contract.ActivityResultContracts")

m = re.search(r'class\s+MainActivity[^{]*\{', s)
if not m:
    raise SystemExit("[!] Cannot locate 'class MainActivity {'")
insert_pos = m.end()

launcher_code = '''
    private val importTemplatesLauncher = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val (ok, fail) = DigitTemplates.importMany(this, uris)
            Toast.makeText(this, "Imported: %d, skipped: %d".format(ok, fail), Toast.LENGTH_LONG).show()
        }
    }
'''
if "importTemplatesLauncher = registerForActivityResult" not in s:
    s = s[:insert_pos] + launcher_code + s[insert_pos:]

idx = s.find("override fun onCreate")
br = s.find("{", idx)
depth = 1; i = br + 1
while i < len(s) and depth > 0:
    if s[i] == '{': depth += 1
    elif s[i] == '}': depth -= 1
    i += 1
body = s[br+1:i-1]

if "btnImportTemplates" in s and ".launch(" not in body:
    handler = '''
        findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
            importTemplatesLauncher.launch(arrayOf("image/*"))
        }
    '''
    body = body + "\n" + handler + "\n"
    s = s[:br+1] + body + s[i-1:]

p.write_text(s, encoding="utf-8")
print("[+] MainActivity cleaned & wired")
PY

echo "==> Building debug APK..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/ || true
