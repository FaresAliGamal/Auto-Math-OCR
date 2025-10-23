set -euo pipefail

python3 - <<'PY'
from pathlib import Path, re
f = Path("app/src/main/java/com/math/app/AutoMathAccessibilityService.kt")
s = f.read_text(encoding="utf-8")
s = s.replace("DigitTemplates.saveTemplate(this, digit, norm)", "DigitTemplates.saveDigit(this, digit, norm)")
s = s.replace("val templates = DigitTemplates.loadTemplates(this)", "val templates = DigitTemplates.loadDigits(this)")
f.write_text(s, encoding="utf-8")
print("[+] Service: switched to saveDigit/loadDigits")
PY

python3 - <<'PY'
from pathlib import Path, re
f = Path("app/src/main/java/com/math/app/DigitTemplates.kt")
s = f.read_text(encoding="utf-8")

s = re.sub(
    r'fun\s+importMany\([^\)]*\)\s*:\s*Pair<Int,Int>\s*\{.*?\n\}', 
    '''fun importMany(ctx: Context, uris: List<Uri>): Pair<Int,Int> {
        var ok = 0; var fail = 0
        for (u in uris) {
            val name = (getDisplayName(ctx, u) ?: "").lowercase()

            val bmp = ctx.contentResolver.openInputStream(u)?.use { ins ->
                BitmapFactory.decodeStream(ins)
            }
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

            if (op != null) { saveOp(ctx, op, norm); ok++ } else { fail++ }
        }
        return ok to fail
    }''',
    s,
    flags=re.S
)
f.write_text(s, encoding="utf-8")
print("[+] DigitTemplates: cleaned importMany (no inline-continue)")
PY

python3 - <<'PY'
from pathlib import Path, re
f = Path("app/src/main/java/com/math/app/MainActivity.kt")
s = f.read_text(encoding="utf-8")

imports_to_add = [
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.widget.Button"),
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.content.Intent"),
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.net.Uri"),
    ("import android.os.Bundle", "import android.os.Bundle\nimport android.widget.Toast"),
    ("import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AppCompatActivity\nimport androidx.appcompat.app.AlertDialog"),
    ("import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AppCompatActivity\nimport androidx.activity.result.contract.ActivityResultContracts")
]
for anchor, add in imports_to_add:
    piece = add.split("\n",1)[1]
    if piece not in s:
        s = s.replace(anchor, add)

s = re.sub(r'\n\s*override\s+fun\s+onActivityResult\([^\)]*\)\s*\{.*?\n\}\s*$', '\n', s, flags=re.S)

s = re.sub(r'private\s+const\s+val\s+REQ_IMPORT_TEMPLATES\s*=\s*\d+\s*\n', '', s)

m = re.search(r'class\s+MainActivity[^{]*\{', s)
if not m:
    raise SystemExit("[!] Could not find class MainActivity {")
insert_pos = m.end()

launcher_prop = '''
    private val importTemplatesLauncher = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val (ok, fail) = DigitTemplates.importMany(this, uris)
            Toast.makeText(this, "Imported: %d, skipped: %d".format(ok, fail), Toast.LENGTH_LONG).show()
        }
    }
'''.rstrip() + "\n"

if "importTemplatesLauncher" not in s:
    s = s[:insert_pos] + "\n" + launcher_prop + s[insert_pos:]

idx = s.find("override fun onCreate")
br = s.find("{", idx); depth=1; i=br+1
while i < len(s) and depth>0:
    if s[i] == '{': depth += 1
    elif s[i] == '}': depth -= 1
    i += 1
body = s[br+1:i-1]

if "btnImportTemplates" not in body or ".launch(" not in body:
    handler = '''
        findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
            // السماح باختيار عدة صور (PNG/صور عامة)
            importTemplatesLauncher.launch(arrayOf("image/*"))
        }
    '''
    body = body + "\n" + handler + "\n"
    s = s[:br+1] + body + s[i-1:]

f.write_text(s, encoding="utf-8")
print("[+] MainActivity: switched to Activity Result API and wired button")
PY

echo "==> Rebuilding APK…"
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
