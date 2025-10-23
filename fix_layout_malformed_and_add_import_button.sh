set -euo pipefail

LAY="app/src/main/res/layout/activity_main.xml"
if [ ! -f "$LAY" ]; then
  echo "[!] Layout not found: $LAY" >&2
  exit 1
fi

python3 - "$LAY" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
x = p.read_text(encoding="utf-8")

m = re.search(r'<\s*([A-Za-z0-9_.:]+)\b[^>]*>', x)
if not m:
    print("[!] Cannot detect root tag", file=sys.stderr); sys.exit(2)
root = m.group(1)
root_close = f"</{root}>"

closes = [m.start() for m in re.finditer(re.escape(root_close), x)]
if len(closes) >= 2:
    last_idx = closes[-1]
    before = x[:last_idx]
    before = re.sub(re.escape(root_close), "", before)
    x = before + x[last_idx:]

btn_block = '''
    <Button
        android:id="@+id/btnImportTemplates"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Import Templates (PNG)"/>
'''.rstrip()

if 'android:id="@+id/btnImportTemplates"' not in x:
    x = re.sub(rf'\s*{re.escape(root_close)}\s*$', "\n" + btn_block + "\n" + root_close + "\n", x, flags=re.S)

p.write_text(x, encoding="utf-8")
print("[+] Fixed layout and ensured Import button exists.")
PY

echo "==> Building debug APK…"
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
