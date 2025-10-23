set -euo pipefail

APP_PKG="com.math.app"
MANIFEST="app/src/main/AndroidManifest.xml"
OVL_LOG="app/src/main/java/com/math/app/OverlayLog.kt"
OVL_REG="app/src/main/java/com/math/app/OverlayRegions.kt"

echo "[1/4] 🔐 تأكيد صلاحية SYSTEM_ALERT_WINDOW في الـ Manifest"
if [ -f "$MANIFEST" ]; then
  cp "$MANIFEST" "$MANIFEST.bak.overlay"
  python3 - "$MANIFEST" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1]); t=p.read_text(encoding="utf-8")
if 'android.permission.SYSTEM_ALERT_WINDOW' not in t:
  t=re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>', t, count=1)
Path(sys.argv[1]).write_text(t, encoding="utf-8")
print("[+] Manifest OK")
PY
else
  echo "[!] Manifest not found: $MANIFEST" >&2
fi

echo "[2/4] 🪟 تصغير نافذة اللوج وتمرير اللمس (OverlayLog.kt)"
if [ -f "$OVL_LOG" ]; then
  cp "$OVL_LOG" "$OVL_LOG.bak.overlay"
  python3 - "$OVL_LOG" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1]); s=p.read_text(encoding="utf-8")

for imp in ["android.view.WindowManager","android.view.Gravity","android.graphics.PixelFormat"]:
  if f"import {imp}" not in s:
    s=s.replace("package com.math.app", f"package com.math.app\nimport {imp}", 1)

s=re.sub(
  r'WindowManager\.LayoutParams\([^)]*\)',
  """WindowManager.LayoutParams(
    WindowManager.LayoutParams.WRAP_CONTENT,
    WindowManager.LayoutParams.WRAP_CONTENT,
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    else
        WindowManager.LayoutParams.TYPE_PHONE,
    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
    PixelFormat.TRANSLUCENT
)""",
  s, flags=re.S
)

def inject_after_params(code:str)->str:
  out=[]; i=0
  pat=re.compile(r'(val\s+params\s*=\s*WindowManager\.LayoutParams\([^)]*\))', re.S)
  while True:
    m=pat.search(code, i)
    if not m:
      out.append(code[i:]); break
    out.append(code[i:m.end()])
    out.append("""
    run {
        val d = try { this@OverlayLog.context.resources.displayMetrics.density } catch (_:Throwable){ 3f }
        params.width = (220 * d).toInt()
        params.height = (140 * d).toInt()
        params.gravity = Gravity.BOTTOM or Gravity.END
        params.alpha = 0.85f
    }
""")
    i=m.end()
  return ''.join(out)

s=inject_after_params(s)

s=re.sub(r'\.setOnTouchListener\s*\{[^}]*\}', 'setOnTouchListener { _, _ -> false }', s)

if "setOnTouchListener" not in s:
  s += """

// تمرير اللمس خارج عناصر التحكم الداخلية
@Suppress("ClickableViewAccessibility")
private fun _ensurePassThrough(root: android.view.View) {
    root.setOnTouchListener { _, _ -> false }
}
"""

Path(sys.argv[1]).write_text(s, encoding="utf-8")
print("[+] OverlayLog patched")
PY
else
  echo "[!] OverlayLog.kt not found: $OVL_LOG" >&2
fi

echo "[3/4] 🟦 تمرير اللمس خارج المستطيلات (OverlayRegions.kt)"
if [ -f "$OVL_REG" ]; then
  cp "$OVL_REG" "$OVL_REG.bak.overlay"
  python3 - "$OVL_REG" <<'PY'
import re,sys
from pathlib import Path
p=Path(sys.argv[1]); s=p.read_text(encoding="utf-8")

for imp in ["android.view.WindowManager","android.graphics.PixelFormat"]:
  if f"import {imp}" not in s:
    s=s.replace("package com.math.app", f"package com.math.app\nimport {imp}", 1)

s=re.sub(
  r'WindowManager\.LayoutParams\([^)]*\)',
  """WindowManager.LayoutParams(
    WindowManager.LayoutParams.MATCH_PARENT,
    WindowManager.LayoutParams.MATCH_PARENT,
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    else
        WindowManager.LayoutParams.TYPE_PHONE,
    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
    PixelFormat.TRANSLUCENT
)""",
  s, flags=re.S
)

s=re.sub(r'setOnTouchListener\s*\{[^}]*\}', 'setOnTouchListener { _, _ -> false }', s)
if "setOnTouchListener { _, _ -> false }" not in s:
  s += """

// مرر اللمس في المساحات الفارغة (خارج المقابض/المستطيلات)
@Suppress("ClickableViewAccessibility")
private fun _passThrough(root: android.view.View) {
    root.setOnTouchListener { _, _ -> false }
}
"""

Path(sys.argv[1]).write_text(s, encoding="utf-8")
print("[+] OverlayRegions patched")
PY
else
  echo "[!] OverlayRegions.kt not found: $OVL_REG" >&2
fi

echo "[4/4] 🏗️ تنظيف ثم بناء APK"
./gradlew clean --no-daemon || true
./gradlew assembleDebug --no-daemon

echo "✅ تم. APK:"
ls -lh app/build/outputs/apk/debug/ || true
