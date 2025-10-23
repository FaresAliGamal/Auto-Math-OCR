set -euo pipefail

APP_PKG="com.math.app"
MANIFEST="app/src/main/AndroidManifest.xml"
MAIN="app/src/main/java/com/math/app/MainActivity.kt"
SVC="app/src/main/java/com/math/app/AutoMathAccessibilityService.kt"
OVL_LOG="app/src/main/java/com/math/app/OverlayLog.kt"
OVL_REG="app/src/main/java/com/math/app/OverlayRegions.kt"

echo "[1/5] 🔐 تعديل AndroidManifest.xml لإضافة صلاحيات الملفات + requestLegacyExternalStorage"

if [ ! -f "$MANIFEST" ]; then
echo "[!] لم يتم العثور على $MANIFEST" >&2
exit 1
fi

cp "$MANIFEST" "$MANIFEST.bak"

python3 - "$MANIFEST" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")

def ensure_uses_perm(src, name):
if name in src: return src
return re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="%s"/>' % name, src, count=1)

t = ensure_uses_perm(t, "android.permission.READ_EXTERNAL_STORAGE")
t = ensure_uses_perm(t, "android.permission.READ_
if 'requestLegacyExternalStorage="true"' not in t:
t = re.sub(r'(<application\b[^>]*?)>',
r'\1 android:requestLegacyExternalStorage="true">', t, count=1)

p.write_text(t, encoding="utf-8")
print("[+] Manifest patched")
PY

echo "[2/5] 📲 MainActivity: طلب صلاحيات الميديا وتشغيل مستعرض الملفات (OpenMultipleDocuments)"
if [ ! -f "$MAIN" ]; then
echo "[!] لم يتم العثور على $MAIN" >&2
exit 1
fi
cp "$MAIN" "$MAIN.bak"

python3 - "$MAIN" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

s = re.sub(r'\n\soverride\s+fun\s+onActivityResult[^)]\s{(?:[^{}]|{[^{}]})}\s', '\n', s, flags=re.S)
s = re.sub(r'\sprivate\s+const\s+val\s+REQ_IMPORT_TEMPLATES\s=\s*\d+\s*', '', s)

def add_after(anchor, line):
if line in s:
return
nonlocal_s = globals()['s']
globals()['s'] = nonlocal_s.replace(anchor, anchor + "\n" + line)

imports = [
"import android.Manifest",
"import android.net.Uri",
"import android.provider.Settings",
"import android.widget.Button",
"import android.widget.Toast",
"import androidx.activity.result.contract.ActivityResultContracts",
"import androidx.appcompat.app.AlertDialog"
]
for imp in imports:
if imp not in s:
s = s.replace("import android.os.Bundle", "import android.os.Bundle\n"+imp)

if "importTemplatesLauncher = registerForActivityResult" not in s:
launcher = '''
// اختيار صور متعددة من الـ SAF
private val importTemplatesLauncher = registerForActivityResult(
ActivityResultContracts.OpenMultipleDocuments()
) { uris: List<Uri> ->
if (uris.isNotEmpty()) {
val (ok, fail) = DigitTemplates.importMany(this, uris)
Toast.makeText(this, "Imported: %d, skipped: %d".format(ok, fail), Toast.LENGTH_LONG).show()
} else {
Toast.makeText(this, "لم يتم اختيار صور", Toast.LENGTH_SHORT).show()
}
}'''.rstrip()
s = re.sub(r'(class\s+MainActivity[^{]*{)', r'\1\n' + launcher + "\n", s)

if "mediaPermsLauncher = registerForActivityResult" not in s:
perms = '''
// طلب صلاحيات الميديا (Android 13+) أو التخزين للأقدم
private val mediaPermsLauncher = registerForActivityResult(
ActivityResultContracts.RequestMultiplePermissions()
) { granted ->
// مجرد تنبيه للمستخدم
val ok = granted.values.any { it }
if (!ok) {
Toast.makeText(this, "لم يتم منح صلاحيات الوصول للصور. يمكن المتابعة عبر مستعرض الملفات.", Toast.LENGTH_LONG).show()
}
}'''.rstrip()
s = re.sub(r'(class\s+MainActivity[^{]*{)', r'\1\n' + perms + "\n", s)

if "private fun ensureMediaPermission" not in s:
fn = '''
private fun ensureMediaPermission() {
val perms = if (android.os.Build.VERSION.SDK_INT >= 33)
arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
else
arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
mediaPermsLauncher.launch(perms)
}'''.rstrip()
s = re.sub(r'(class\s+MainActivity[^{]*{)', r'\1\n' + fn + "\n", s)

m = re.search(r'override\s+fun\s+onCreate\s\s{', s)
if m:
br = m.end(); depth=1; i=br
while i < len(s) and depth>0:
if s[i]=='{': depth+=1
elif s[i]=='}': depth-=1
i+=1
body = s[br:i-1]
need = "btnImportTemplates" in s and ".launch(" not in body
if need:
body += '''
// زر استيراد القوالب
findViewById<Button>(R.id.btnImportTemplates).setOnClickListener {
// اطلب صلاحيات الميديا (مش ضرورية للـ SAF لكنها مفيدة لأجهزة قديمة)
ensureMediaPermission()
// افتح مستعرض الملفات لاختيار صور متعددة
importTemplatesLauncher.launch(arrayOf("image/*"))
}'''
s = s[:br] + body + s[i-1:]

Path(sys.argv[1]).write_text(s, encoding="utf-8")
print("[+] MainActivity patched")
PY

echo "[3/5] 🪟 ضبط حجم وموضع نافذة اللوج + تمرير اللمس خارج المستطيلات"
if [ -f "$SVC" ]; then
cp "$SVC" "$SVC.bak2" || true
python3 - "$SVC" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text(encoding="utf-8")

s = re.sub(r'^\sparams.(gravity|width|height|alpha)\s=.*?$', '', s, flags=re.M)

s = re.sub(r'WindowManager.LayoutParams[^)]*',
"""WindowManager.LayoutParams(
WindowManager.LayoutParams.MATCH_PARENT,
WindowManager.LayoutParams.MATCH_PARENT,
if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
else
WindowManager.LayoutParams.TYPE_PHONE,
WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
android.graphics.PixelFormat.TRANSLUCENT
)""", s, flags=re.S)

p.write_text(s, encoding="utf-8")
print("[+] Service params normalized")
PY
else
echo "[!] تحذير: لم يتم العثور على $SVC (تخطي)"
fi

if [ -f "$OVL_LOG" ]; then
cp "$OVL_LOG" "$OVL_LOG.bak" || true
python3 - "$OVL_LOG" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text(encoding="utf-8")

for imp in ["android.view.WindowManager", "android.view.Gravity"]:
if ("import %s" % imp) not in s:
s = s.replace("package com.math.app", "package com.math.app\nimport %s" % imp, 1)

def add_block(code):
pat = re.compile(r'(val\s+params\s*=\s*WindowManager.LayoutParams[^)]*)', re.S)
def repl(m):
return m.group(1) + r"""
val d = resources.displayMetrics.density
params.width = (260 * d).toInt()
params.height = (180 * d).toInt()
params.alpha = 0.7f
params.gravity = Gravity.BOTTOM or Gravity.END
"""
return pat.sub(repl, code, count=1)

s2 = add_block(s)
if s2 == s:
if "// LOG_PARAMS_HELPER" not in s:
s += """

// LOG_PARAMS_HELPER
// ضع الكود التالي بعد إنشاء params لو احتجت يدوياً:
// val d = resources.displayMetrics.density
// params.width = (260 * d).toInt()
// params.height = (180 * d).toInt()
// params.alpha = 0.7f
// params.gravity = Gravity.BOTTOM or Gravity.END
"""
else:
s = s2

p.write_text(s, encoding="utf-8")
print("[+] OverlayLog sized & positioned")
PY
else
echo "[!] تحذير: لم يتم العثور على $OVL_LOG (تخطي)"
fi

if [ -f "$OVL_REG" ]; then
cp "$OVL_REG" "$OVL_REG.bak" || true
python3 - "$OVL_REG" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text(encoding="utf-8")

for imp in ["android.view.WindowManager"]:
if ("import %s" % imp) not in s:
s = s.replace("package com.math.app", "package com.math.app\nimport %s" % imp, 1)

s = re.sub(r'WindowManager.LayoutParams[^)]*',
"""WindowManager.LayoutParams(
WindowManager.LayoutParams.MATCH_PARENT,
WindowManager.LayoutParams.MATCH_PARENT,
if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
else
WindowManager.LayoutParams.TYPE_PHONE,
WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
android.graphics.PixelFormat.TRANSLUCENT
)""", s, flags=re.S)

s = re.sub(r'setOnTouchListener\s*{\s*[^}]?(return\s+)?true\s;?\s*}', 'setOnTouchListener { _, _ -> false }', s)

if "setOnTouchListener { _, _ -> false }" not in s:
s += """

// يجعل الروت لا يستهلك اللمس خارج العناصر الداخلية (اللمس يمر للشاشة)
@Suppress("ClickableViewAccessibility")
private fun _ensureRootPassThrough(root: android.view.View) {
root.setOnTouchListener { _, _ -> false }
}
"""

p.write_text(s, encoding="utf-8")
print("[+] OverlayRegions will pass touches outside rectangles")
PY
else
echo "[!] تحذير: لم يتم العثور على $OVL_REG (تخطي)"
fi

echo "[4/5] 🧹 تنظيف المشروع"
./gradlew clean --no-daemon || true

echo "[5/5] 🏗️ بناء Debug APK"
./gradlew assembleDebug --no-daemon

echo "✅ تم — راجع المخرجات:"
ls -lh app/build/outputs/apk/debug/ || true
