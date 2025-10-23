set -euo pipefail

echo "[1/5] 🔧 إصلاح واجهة رفع الصور (MainActivity.kt)"
python3 - <<'PY'
import re
from pathlib import Path
p = Path("app/src/main/java/com/math/app/MainActivity.kt")
if not p.exists(): raise SystemExit("[!] الملف غير موجود: MainActivity.kt")

s = p.read_text(encoding="utf-8")

s = re.sub(r'\s*private\s+const\s+val\s+REQ_IMPORT_TEMPLATES\s*=\s*\d+\s*', '', s)
s = re.sub(r'\n\s*override\s+fun\s+onActivityResult\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\}\s*', '\n', s, flags=re.S)
s = re.sub(r'startActivityForResult\s*\([^)]*\)\s*', '', s)

imports = [
    "import android.widget.Button",
    "import android.widget.Toast",
    "import android.content.Intent",
    "import android.net.Uri",
    "import androidx.appcompat.app.AlertDialog",
    "import androidx.activity.result.contract.ActivityResultContracts",
]
for imp in imports:
    if imp not in s: s = s.replace("import android.os.Bundle", "import android.os.Bundle\n" + imp)

if "importTemplatesLauncher = registerForActivityResult" not in s:
    launcher = '''
    // Launcher for importing templates
    private val importTemplatesLauncher = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isNotEmpty()) {
            val (ok, fail) = DigitTemplates.importMany(this, uris)
            Toast.makeText(this, "Imported: %d, skipped: %d".format(ok, fail), Toast.LENGTH_LONG).show()
        }
    }
    '''
    s = re.sub(r'(class\s+MainActivity[^{]*\{)', r'\1\n' + launcher, s)

m = re.search(r'override\s+fun\s+onCreate\s*\([^)]*\)\s*\{', s)
if m:
    start = m.end()
    br, depth, i = start, 1, start
    while i < len(s) and depth > 0:
        if s[i] == '{': depth += 1
        elif s[i] == '}': depth -= 1
        i += 1
    body = s[br:i-1]
    if "btnImportTemplates" in s and ".launch(" not in body:
        handler = '''
        // Import Templates button click
        findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
            importTemplatesLauncher.launch(arrayOf("image/*"))
        }
        '''
        body += "\n" + handler + "\n"
        s = s[:br] + body + s[i-1:]
p.write_text(s, encoding="utf-8")
print("[+] تم إصلاح MainActivity.kt")
PY

echo "[2/5] 🧩 إصلاح AutoMathAccessibilityService.kt (نافذة اللوج + لمس المستطيلات)"
python3 - <<'PY'
import re
from pathlib import Path
p = Path("app/src/main/java/com/math/app/AutoMathAccessibilityService.kt")
if not p.exists(): raise SystemExit("[!] الملف غير موجود: AutoMathAccessibilityService.kt")

s = p.read_text(encoding="utf-8")

pattern = re.compile(r'WindowManager\.LayoutParams\([^)]*\)', re.S)
replacement = """WindowManager.LayoutParams(
    WindowManager.LayoutParams.MATCH_PARENT,
    WindowManager.LayoutParams.MATCH_PARENT,
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    else
        WindowManager.LayoutParams.TYPE_PHONE,
    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
    PixelFormat.TRANSLUCENT
)"""
s = pattern.sub(replacement, s)

if "params.gravity" in s:
    s = re.sub(r'params\.gravity\s*=\s*[^\\n]*', 'params.gravity = Gravity.BOTTOM or Gravity.END', s)
else:
    s += "\nparams.gravity = Gravity.BOTTOM or Gravity.END\n"

if "params.width" not in s:
    s += "\nparams.width = 600\nparams.height = 400\nparams.alpha = 0.8f\n"

if 'setOnTouchListener' in s:
    s = re.sub(
        r'setOnTouchListener\s*\{[^\}]*\}',
        """setOnTouchListener { v, event ->
            v.performClick()
            when (event.action) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP -> {
                    // داخل المستطيل
                    true
                }
                else -> false // خارج المستطيل → يمرر اللمس
            }
        }""",
        s,
    )

p.write_text(s, encoding="utf-8")
print("[+] تم إصلاح AutoMathAccessibilityService.kt")
PY

echo "[3/5] 🧠 إصلاح DigitTemplates.kt (لو ناقص)"
if [ -f app/src/main/java/com/math/app/DigitTemplates.kt ]; then
  grep -q "fun importMany" app/src/main/java/com/math/app/DigitTemplates.kt || echo "[!] تحذير: importMany مفقودة"
else
  echo "[!] تحذير: DigitTemplates.kt غير موجود"
fi

echo "[4/5] 🧹 تنظيف المشروع"
./gradlew clean || true

echo "[5/5] 🏗️ بناء التطبيق..."
./gradlew --no-daemon assembleDebug

echo "✅ تم الانتهاء بنجاح!"
echo "📦 APKs:"
ls -lh app/build/outputs/apk/debug/ || true
