set -euo pipefail

LAY="app/src/main/res/layout/activity_main.xml"
if [ ! -f "$LAY" ]; then
  echo "[!] Layout not found: $LAY" >&2
  exit 1
fi

echo "[*] Backing up original layout to activity_main_backup.xml ..."
cp "$LAY" "${LAY}.bak"

python3 - "$LAY" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

text = re.sub(r'(</\s*[A-Za-z0-9_.:]+\s*>)\s*[^<]*$', r'\1\n', text)

lines = text.strip().splitlines()
root_tag = None
fixed_lines = []

for line in lines:
    if root_tag is None and re.search(r'<\s*([A-Za-z0-9_.:]+)\b', line):
        m = re.search(r'<\s*([A-Za-z0-9_.:]+)\b', line)
        root_tag = m.group(1)
    if root_tag and re.search(fr'</\s*{root_tag}\s*>', line):
        if any(fr'</{root_tag}>' in l for l in fixed_lines):
            continue
    fixed_lines.append(line)

text = "\n".join(fixed_lines)

if 'btnImportTemplates' not in text:
    insert_btn = '''
    <Button
        android:id="@+id/btnImportTemplates"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Import Templates (PNG)"/>'''
    text = re.sub(fr'(</{root_tag}>\s*)$', insert_btn + r'\n\1', text)

p.write_text(text, encoding="utf-8")
print("[+] Cleaned and repaired layout XML successfully.")
PY

echo "==> Rebuilding APK..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
