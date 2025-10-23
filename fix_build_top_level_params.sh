set -euo pipefail

SVC="app/src/main/java/com/math/app/AutoMathAccessibilityService.kt"
if [ ! -f "$SVC" ]; then
  echo "[!] File not found: $SVC" >&2
  exit 1
fi

echo "[*] Backup AutoMathAccessibilityService.kt -> .bak"
cp "$SVC" "$SVC.bak"

python3 - "$SVC" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')

s = re.sub(r'^\s*params\.(gravity|width|height|alpha)\s*=.*?\n', '', s, flags=re.M)

s = re.sub(
    r'WindowManager\.LayoutParams\([^)]*\)',
    """WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        (if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
            android.view.WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            android.view.WindowManager.LayoutParams.TYPE_PHONE),
        android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
        android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        android.graphics.PixelFormat.TRANSLUCENT
    )""",
    s,
    flags=re.S
)

def inject_after_params_block(code: str) -> str:
    out = []
    i = 0
    while i < len(code):
        m = re.search(r'(val\s+params\s*=\s*WindowManager\.LayoutParams\([^)]*\))', code[i:], flags=re.S)
        if not m:
            out.append(code[i:])
            break
        start = i + m.start()
        end = i + m.end()
        out.append(code[i:start])
        out.append(code[start:end])

        tail = code[end:end+2000]
        has_gravity = re.search(r'params\.gravity\s*=', tail)
        has_width   = re.search(r'params\.width\s*=', tail)
        has_height  = re.search(r'params\.height\s*=', tail)
        has_alpha   = re.search(r'params\.alpha\s*=', tail)

        if not (has_gravity and has_width and has_height and has_alpha):
            out.append("""
params.gravity = android.view.Gravity.BOTTOM or android.view.Gravity.END
params.width = 600
params.height = 400
params.alpha = 0.8f
""")
        i = end
    return ''.join(out)

s = inject_after_params_block(s)


Path(sys.argv[1]).write_text(s, encoding='utf-8')
print("[+] Patched AutoMathAccessibilityService.kt successfully")
PY

echo "[*] Clean & Build..."
./gradlew clean --no-daemon
./gradlew assembleDebug --no-daemon

echo "[*] APKs:"
ls -lh app/build/outputs/apk/debug/ || true
