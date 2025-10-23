set -euo pipefail

MA="app/src/main/java/com/math/app/MainActivity.kt"
if [ ! -f "$MA" ]; then
  echo "[!] Missing $MA" >&2
  exit 1
fi

echo "[*] Backing up MainActivity.kt -> MainActivity.kt.bak"
cp "$MA" "$MA.bak"

python3 - "$MA" <<'PY'
import re, sys
from pathlib import Path

fp = Path(sys.argv[1])
code = fp.read_text(encoding="utf-8")

m = re.search(r'\bclass\s+MainActivity\b[^{]*\{', code)
if not m:
    print("[!] Cannot find 'class MainActivity {'", file=sys.stderr); sys.exit(2)

class_start = m.start()
class_header_end = m.end()

depth = 1
i = class_header_end
while i < len(code) and depth > 0:
    c = code[i]
    if c == '{': depth += 1
    elif c == '}': depth -= 1
    i += 1
if depth != 0:
    print("[!] Braces not balanced in MainActivity", file=sys.stderr); sys.exit(2)

prefix = code[:class_start]
class_header = code[class_start:class_header_end]
class_body = code[class_header_end:i-1]

class_body = re.sub(r'\s*private\s+const\s+val\s+REQ_IMPORT_TEMPLATES\s*=\s*\d+\s*', '', class_body)
class_body = re.sub(r'\n\s*override\s+fun\s+onActivityResult\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\}\s*', '\n', class_body, flags=re.S)
class_body = re.sub(r'startActivityForResult\s*\([^)]*\)\s*', '', class_body)

def ensure_import(block, anchor, imp):
    if imp not in block:
        if anchor in block:
            block = block.replace(anchor, anchor + "\n" + imp)
        else:
            block = re.sub(r'(\nimport[^\n]*\n)*', lambda m: (m.group(0) or "") + imp + "\n", block, count=1)
    return block

prefix = ensure_import(prefix, "import android.os.Bundle", "import android.widget.Button")
prefix = ensure_import(prefix, "import android.os.Bundle", "import android.widget.Toast")
prefix = ensure_import(prefix, "import android.os.Bundle", "import android.content.Intent")
prefix = ensure_import(prefix, "import android.os.Bundle", "import android.net.Uri")
prefix = ensure_import(prefix, "import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AlertDialog")
prefix = ensure_import(prefix, "import androidx.appcompat.app.AppCompatActivity", "import androidx.activity.result.contract.ActivityResultContracts")

if "importTemplatesLauncher = registerForActivityResult" not in class_body:
    launcher = '''
    // Activity Result launcher for bulk template import
    private val importTemplatesLauncher = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val (ok, fail) = DigitTemplates.importMany(this, uris)
            Toast.makeText(this, "Imported: %d, skipped: %d".format(ok, fail), Toast.LENGTH_LONG).show()
        }
    }
'''
    class_body = launcher + class_body

oncreate = re.search(r'override\s+fun\s+onCreate\s*\(\s*savedInstanceState:\s*Bundle\?\s*\)\s*\{', class_body)
if oncreate:
    br = oncreate.end()
    depth = 1
    j = br
    while j < len(class_body) and depth > 0:
        if class_body[j] == '{': depth += 1
        elif class_body[j] == '}': depth -= 1
        j += 1
    oncreate_body = class_body[br:j-1]
    if "btnImportTemplates" in class_body and ".launch(" not in oncreate_body:
        handler = '''
        // Import Templates button -> system picker (multiple images)
        findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
            importTemplatesLauncher.launch(arrayOf("image/*"))
        }
        '''
        oncreate_body = oncreate_body + "\n" + handler + "\n"
        class_body = class_body[:br] + oncreate_body + class_body[j-1:]
else:
    print("[!] onCreate not found – skipped adding button handler", file=sys.stderr)

clean = prefix + class_header + class_body + "\n}\n"
fp.write_text(clean, encoding="utf-8")
print("[+] MainActivity surgically cleaned and fixed.")
PY

python3 - <<'PY'
from pathlib import Path
svc = Path("app/src/main/java/com/math/app/AutoMathAccessibilityService.kt")
if svc.exists():
    s = svc.read_text(encoding="utf-8")
    s = s.replace("DigitTemplates.saveTemplate(this, digit, norm)", "DigitTemplates.saveDigit(this, digit, norm)")
    s = s.replace("DigitTemplates.loadTemplates(this)", "DigitTemplates.loadDigits(this)")
    svc.write_text(s, encoding="utf-8")
    print("[+] Service references OK")
else:
    print("[!] Service not found (skip)")
PY

echo "==> Rebuilding APK..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/ || true
