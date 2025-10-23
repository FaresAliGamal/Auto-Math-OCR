set -euo pipefail

f="app/src/main/java/com/math/app/OverlayRegions.kt"
if grep -q '[^A-Za-z]LayoutParams' "$f"; then
  sed -i 's/\([^A-Za-z]\)LayoutParams/\1ViewGroup.LayoutParams/g' "$f"
  echo "[+] Fixed LayoutParams -> ViewGroup.LayoutParams in OverlayRegions.kt"
else
  echo "[=] OverlayRegions.kt already uses ViewGroup.LayoutParams"
fi

mf="app/src/main/java/com/math/app/MainActivity.kt"
python3 - <<'PY'
import re
from pathlib import Path

p = Path("app/src/main/java/com/math/app/MainActivity.kt")
s = p.read_text(encoding="utf-8")

if "OverlayRegions.toggle(this)" in s:
    print("[=] Long-press handler already present.")
else:
    m = re.search(r'override\s+fun\s+onCreate\s*\([^)]*\)\s*\{', s)
    if not m:
        print("[!] Could not find onCreate() in MainActivity.kt; aborting injection.")
    else:
        start = m.end()
        depth = 1
        i = start
        while i < len(s) and depth > 0:
            if s[i] == '{': depth += 1
            elif s[i] == '}': depth -= 1
            i += 1
        oncreate_body = s[start:i-1]

        inject_block = '''
        // Long-press to open/close regions editor
        findViewById<Button>(R.id.btnRun).setOnLongClickListener {
            try { OverlayRegions.toggle(this) } catch (_: Exception) {}
            true
        }
'''.rstrip() + "\n"

        click_m = re.search(r'findViewById<Button>\(R\.id\.btnRun\)\.setOnClickListener\s*\{.*?\}\s*', oncreate_body, flags=re.S)
        if click_m:
            new_body = oncreate_body[:click_m.end()] + "\n" + inject_block + oncreate_body[click_m.end():]
        else:
            new_body = oncreate_body + "\n" + inject_block

        new_s = s[:start] + new_body + s[i-1:]
        p.write_text(new_s, encoding="utf-8")
        print("[+] Injected long-press handler into onCreate()")
PY

echo "==> Building..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
