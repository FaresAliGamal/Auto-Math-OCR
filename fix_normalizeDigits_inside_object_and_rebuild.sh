set -euo pipefail

TEMPL="app/src/main/java/com/math/app/TemplateOcr.kt"
[ -f "$TEMPL" ] || { echo "[!] TemplateOcr.kt not found"; exit 1; }

echo "[*] Backup -> TemplateOcr.kt.bak2"
cp "$TEMPL" "$TEMPL.bak2"

python3 - "$TEMPL" <<'PY'
import sys, re
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

m = re.search(r'\bobject\s+TemplateOcr\s*\{', s)
if not m:
    print("[!] لم أجد object TemplateOcr {", file=sys.stderr); sys.exit(2)

start = m.end()
depth = 1
i = start
while i < len(s) and depth > 0:
    if s[i] == '{': depth += 1
    elif s[i] == '}': depth -= 1
    i += 1
if depth != 0:
    print("[!] الأقواس غير متوازنة داخل TemplateOcr", file=sys.stderr); sys.exit(2)

obj_body = s[start:i-1]

if re.search(r'\bfun\s+normalizeDigits\s*\(', obj_body) is None:
    shim = r"""
    // --- shim: keep compatibility with old calls ---
    fun normalizeDigits(bmp: android.graphics.Bitmap): android.graphics.Bitmap? {
        return normalizeGlyph(bmp)
    }
""".rstrip("\n")
    s = s[:i-1] + "\n" + shim + "\n" + s[i-1:]

def remove_top_level(sh: str) -> str:
    result = []
    last = 0
    for mm in re.finditer(r'\bfun\s+normalizeDigits\s*\([^)]*\)\s*:\s*[^{\n]+\s*\{', sh):
        fn_start = mm.start()
        inside = (fn_start >= start and fn_start < i)
        if inside:
            continue  
        d = 1
        j = mm.end()
        while j < len(sh) and d > 0:
            if sh[j] == '{': d += 1
            elif sh[j] == '}': d -= 1
            j += 1
        result.append(sh[last:fn_start])
        last = j
    result.append(sh[last:])
    return ''.join(result)

s = remove_top_level(s)

p.write_text(s, encoding="utf-8")
print("[+] normalizeDigits الآن داخل TemplateOcr")
PY

echo "[*] Rebuild..."
./gradlew assembleDebug --no-daemon

echo "[*] APKs:"
ls -lh app/build/outputs/apk/debug/ || true
