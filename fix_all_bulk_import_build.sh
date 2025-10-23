set -euo pipefail

echo "[1/4] Patch DigitTemplates.kt (helpers + imports + calls)..."
DT="app/src/main/java/com/math/app/DigitTemplates.kt"
if [ ! -f "$DT" ]; then
  echo "[!] Missing $DT" >&2
  exit 1
fi

python3 - "$DT" <<'PY'
import sys, re
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

def add_import(s, imp):
    if imp not in s:
        s = s.replace("package com.math.app", "package com.math.app\n"+imp, 1)
    return s

s = add_import(s, "import android.graphics.BitmapFactory")
s = add_import(s, "import android.net.Uri")
s = add_import(s, "import android.provider.OpenableColumns")

s = s.replace(".putString(keyDigit(digit), toB64(bmp28))", ".putString(keyDigit(digit), bmp28.toB64())")
s = s.replace(".putString(keyOp(op), toB64(bmp28))", ".putString(keyOp(op), bmp28.toB64())")

need_helpers = ("fun getDisplayName(" not in s) or (".toB64(" not in s) or ("fromB64(" not in s)
if need_helpers:
    insert_at = s.rfind("}")
    helpers = """

    // ===== Helpers =====
    private fun Bitmap.toB64(): String {
        val baos = java.io.ByteArrayOutputStream()
        this.compress(Bitmap.CompressFormat.PNG, 100, baos)
        return android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
    }

    private fun fromB64(b64: String): Bitmap? {
        return try {
            val bytes = android.util.Base64.decode(b64, android.util.Base64.NO_WRAP)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (e: Exception) { null }
    }

    fun getDisplayName(ctx: Context, uri: Uri): String? {
        val c = ctx.contentResolver.query(uri, null, null, null, null)
        c?.use {
            val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (it.moveToFirst() && idx >= 0) return it.getString(idx)
        }
        return uri.lastPathSegment
    }
    """
    if insert_at != -1:
        s = s[:insert_at] + helpers + "\n}\n"

if not s.rstrip().endswith("}"):
    s = s.rstrip() + "\n}\n"

p.write_text(s, encoding="utf-8")
print("[+] DigitTemplates.kt patched")
PY

echo "[2/4] Fix service to use saveDigit/loadDigits..."
SVC="app/src/main/java/com/math/app/AutoMathAccessibilityService.kt"
if [ -f "$SVC" ]; then
  python3 - "$SVC" <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/math/app/AutoMathAccessibilityService.kt")
s = p.read_text(encoding="utf-8")
s = s.replace("DigitTemplates.saveTemplate(this, digit, norm)", "DigitTemplates.saveDigit(this, digit, norm)")
s = s.replace("val templates = DigitTemplates.loadTemplates(this)", "val templates = DigitTemplates.loadDigits(this)")
p.write_text(s, encoding="utf-8")
print("[+] Service references updated")
PY
else
  echo "[!] Service file not found (skipped): $SVC"
fi

echo "[3/4] Clean MainActivity (remove old onActivityResult + const; ensure imports & launcher)..."
MA="app/src/main/java/com/math/app/MainActivity.kt"
if [ ! -f "$MA" ]; then
  echo "[!] Missing $MA" >&2
  exit 1
fi

python3 - "$MA" <<'PY'
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
    raise SystemExit("[!] Cannot locate 'class MainActivity {'.")
insert_pos = m.end()
if "importTemplatesLauncher = registerForActivityResult" not in s:
    launcher = '''
    private val importTemplatesLauncher = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val (ok, fail) = DigitTemplates.importMany(this, uris)
            Toast.makeText(this, "Imported: %d, skipped: %d".format(ok, fail), Toast.LENGTH_LONG).show()
        }
    }
'''
    s = s[:insert_pos] + launcher + s[insert_pos:]

idx = s.find("override fun onCreate")
br = s.find("{", idx); depth=1; i=br+1
while i < len(s) and depth>0:
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

echo "[4/4] Build debug APK..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/ || true
