set -euo pipefail

MA="app/src/main/java/com/math/app/MainActivity.kt"
if [ ! -f "$MA" ]; then
  echo "[!] Missing $MA" >&2
  exit 1
fi

python3 - "$MA" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

s = re.sub(r'\s*private\s+const\s+val\s+REQ_IMPORT_TEMPLATES\s*=\s*\d+\s*', '', s)

s = re.sub(r'\n\s*override\s+fun\s+onActivityResult\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\}\s*', '\n', s, flags=re.S)

s = re.sub(r'startActivityForResult\s*\([^)]*?\)\s*', '/* removed startActivityForResult */', s)

def ensure_import(block, anchor, imp):
    if imp not in block:
        block = block.replace(anchor, anchor + "\n" + imp)
    return block

s = ensure_import(s, "import android.os.Bundle", "import android.widget.Button")
s = ensure_import(s, "import android.os.Bundle", "import android.widget.Toast")
s = ensure_import(s, "import android.os.Bundle", "import android.content.Intent")
s = ensure_import(s, "import android.os.Bundle", "import android.net.Uri")
s = ensure_import(s, "import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AlertDialog")
s = ensure_import(s, "import androidx.appcompat.app.AppCompatActivity", "import androidx.activity.result.contract.ActivityResultContracts")

m = re.search(r'class\s+MainActivity[^{]*\{', s)
if not m:
    print("[!] Cannot find 'class MainActivity {' in file", file=sys.stderr)
    sys.exit(2)

insert_pos = m.end()
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
if "importTemplatesLauncher = registerForActivityResult" not in s:
    s = s[:insert_pos] + launcher + s[insert_pos:]

oncreate_idx = s.find("override fun onCreate")
if oncreate_idx != -1:
    br = s.find("{", oncreate_idx)
    depth = 1; i = br + 1
    while i < len(s) and depth > 0:
        if s[i] == '{': depth += 1
        elif s[i] == '}': depth -= 1
        i += 1
    body = s[br+1:i-1]
    if "btnImportTemplates" in s and ".launch(" not in body:
        handler = '''
        // Import Templates button -> system picker (multiple images)
        findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
            importTemplatesLauncher.launch(arrayOf("image/*"))
        }
        '''
        body = body + "\n" + handler + "\n"
        s = s[:br+1] + body + s[i-1:]

last_brace = s.rfind("}")
if last_brace != -1:
    s = s[:last_brace+1] + "\n"

p.write_text(s, encoding="utf-8")
print("[+] MainActivity cleaned & wired")
PY

echo "==> Rebuilding APK..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/ || true
