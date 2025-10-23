set -euo pipefail

python3 - <<'PY'
import re
from pathlib import Path

p = Path("app/src/main/java/com/math/app/MainActivity.kt")
s = p.read_text(encoding="utf-8")

if "OverlayRegions.toggle(this)" in s:
    print("[=] Long-press handler already present.")
else:
    pattern = r'(findViewById<Button>\(R\.id\.btnRun\)\.setOnClickListener[^\n]*\n\s*\{.*?\}\s*\n)'
    m = re.search(pattern, s, flags=re.S)
    if m:
        inject = m.group(1) + """
        // Long-press to open/close regions editor
        findViewById<Button>(R.id.btnRun).setOnLongClickListener {
            try { OverlayRegions.toggle(this) } catch (_: Exception) {}
            true
        }
"""
        s = s[:m.start(1)] + inject + s[m.end(1):]
        p.write_text(s, encoding="utf-8")
        print("[+] Long-press handler injected into MainActivity.kt")
    else:
        print("[!] Could not find btnRun click block; no injection done.")
PY

echo "==> Building..."
./gradlew --no-daemon assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
