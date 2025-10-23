set -euo pipefail

mkdir -p app/src/main/java/com/math/app

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
        ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
            .edit().putString(keyDigit(digit), toB64(bmp28)).apply()
    }
    fun loadDigits(ctx: Context): Map<Int, Bitmap> {
        val sp = ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
        val out = mutableMapOf<Int, Bitmap>()
        for (d in 0..9) {
            sp.getString(keyDigit(d), null)?.let { b64 ->
                fromB64(b64)?.also { out[d] = it }
            }
        }
        return out
    }

    // ===== Operators (+ - × ÷) =====
    fun saveOp(ctx: Context, op: String, bmp28: Bitmap) {
        require(op in listOf("+","-","×","÷"))
        ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
            .edit().putString(keyOp(op), toB64(bmp28)).apply()
    }
    fun loadOps(ctx: Context): Map<String, Bitmap> {
        val sp = ctx.getSharedPreferences(SP, Context.MODE_PRIVATE)
        val out = mutableMapOf<String, Bitmap>()
        for (op in listOf("+","-","×","÷")) {
            sp.getString(keyOp(op), null)?.let { b64 ->
                fromB64(b64)?.also { out[op] = it }
            }
        }
        return out
    }

    // ===== Bulk import from gallery URIs =====
    // Maps file names to digit/op automatically:
    //   0.png..9.png  OR names starting with those digits
    //   plus/+ , minus/- , times/x/mul/*/× , divide/div/÷// 
    fun importMany(ctx: Context, uris: List<Uri>): Pair<Int,Int> {
        var ok = 0; var fail = 0
        for (u in uris) {
            val name = (getDisplayName(ctx, u) ?: "").lowercase()
            val bmp = ctx.contentResolver.openInputStream(u)?.use { ins ->
                BitmapFactory.decodeStream(ins)
            } ?: run { fail++; continue }

            val norm = TemplateOcr.normalizeGlyph(bmp) ?: run { fail++; continue }

            val mappedDigit = name.firstOrNull()?.digitToIntOrNull()
            if (mappedDigit != null) {
                saveDigit(ctx, mappedDigit, norm); ok++; continue
            }

            val op = when {
                name.contains("plus") || name == "+" -> "+"
                name.contains("minus") || name == "-" -> "-"
                name.contains("times") || name.contains("mul") || name.contains("x") || name.contains("asterisk") || name == "*" || name.contains("×") -> "×"
                name.contains("div") || name.contains("divide") || name == "/" || name.contains("÷") -> "÷"
                else -> null
            }
            if (op != null) { saveOp(ctx, op, norm); ok++ } else fail++
        }
        return ok to fail
    }

    private fun toB64(bmp28: Bitmap): String {
        val baos = ByteArrayOutputStream()
        bmp28.compress(Bitmap.CompressFormat.PNG, 100, baos)
        return Base64.encodeToString(baos.toByteArray(), Base64.DEFAULT)
    }
    private fun fromB64(b64: String): Bitmap? {
        val bytes = Base64.decode(b64, Base64.DEFAULT)
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }
    private fun getDisplayName(ctx: Context, uri: Uri): String? {
        val c = ctx.contentResolver.query(uri, null, null, null, null) ?: return null
        c.use {
            val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            return if (it.moveToFirst() && idx >= 0) it.getString(idx) else null
        }
    }
}
KOT

if [ ! -f app/src/main/java/com/math/app/TemplateOcr.kt ]; then
cat > app/src/main/java/com/math/app/TemplateOcr.kt <<'KOT'
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
}
KOT
fi

# 3) أضف زر "Import Templates" و هندلر الاستيراد المتعدد من المعرض في MainActivity
python3 - <<'PY'
from pathlib import Path, re
p = Path("app/src/main/java/com/math/app/MainActivity.kt")
s = p.read_text(encoding="utf-8")

# Imports
need = [
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.widget.Button"),
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.content.Intent"),
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.net.Uri"),
    ("import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AppCompatActivity\nimport androidx.appcompat.app.AlertDialog")
]
for anchor, add in need:
    if add.split("\n",1)[1] not in s:
        s = s.replace(anchor, add)

# Add Import button to layout if not exists
lay = Path("app/src/main/res/layout/activity_main.xml")
lx = lay.read_text(encoding="utf-8")
if 'android:id="@+id/btnImportTemplates"' not in lx:
    lx = lx.replace("</LinearLayout>", "", 1) if lx.strip().endswith("</LinearLayout>") else lx
    extra = '''
    <Button
        android:id="@+id/btnImportTemplates"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Import Templates (PNG)"/>
</LinearLayout>
'''
    if "</LinearLayout>" in lx:
        lx = re.sub(r"</LinearLayout>\s*$", extra, lx, flags=re.S)
    else:
        lx = lx + "\n" + extra
    lay.write_text(lx, encoding="utf-8")

# Add request code + onActivityResult + handler
if "private const val REQ_IMPORT_TEMPLATES" not in s:
    s = s.replace(
        "class MainActivity",
        "private const val REQ_IMPORT_TEMPLATES = 991\n\nclass MainActivity"
    )

if "onActivityResult" not in s:
    s = s.replace(
        "override fun onCreate(savedInstanceState: Bundle?) {",
        "override fun onCreate(savedInstanceState: Bundle?) {"
    )
    s += '''

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_IMPORT_TEMPLATES && resultCode == RESULT_OK && data != null) {
            val uris = mutableListOf<Uri>()
            data.clipData?.let { cd ->
                for (i in 0 until cd.itemCount) uris.add(cd.getItemAt(i).uri)
            } ?: run {
                data.data?.let { uris.add(it) }
            }
            if (uris.isNotEmpty()) {
                val (ok, fail) = DigitTemplates.importMany(this, uris)
                android.widget.Toast.makeText(this, "Imported: $ok, skipped: $fail", android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }
'''
# Wire click handler
idx = s.find("override fun onCreate")
br = s.find("{", idx); depth=1; i=br+1
while i < len(s) and depth>0:
    if s[i]=='{': depth+=1
    elif s[i]=='}': depth-=1
    i+=1
body = s[br+1:i-1]
if "btnImportTemplates" not in body:
    handler = '''
        findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            startActivityForResult(intent, REQ_IMPORT_TEMPLATES)
        }
'''
    body = body + "\n" + handler
    s = s[:br+1] + body + s[i-1:]
p.write_text(s, encoding="utf-8")
print("[+] MainActivity wired for bulk import")
PY

echo "==> Building debug APK…"
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
