set -euo pipefail

F="app/src/main/java/com/math/app/AutoMathAccessibilityService.kt"
if [ ! -f "$F" ]; then
  echo "[!] File not found: $F" >&2
  exit 1
fi

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

fp = Path(sys.argv[1])
src = fp.read_text(encoding="utf-8")


pattern = re.compile(
    r"""(\n\s*var\s+byTemplate\s*:\s*String\?\s*=\s*null\s*\n.*?
        )(if\s*\(\s*byTemplate\s*!=\s*null\s*\)\s*\{\s*
            ansTexts\[i-1]\s*=\s*byTemplate;\s*readCount\+\+;\s*done\(\);\s*continue\s*;\s*
        \})""",
    re.S | re.X
)

def repl(m):
    prefix = m.group(1)
    return (
        prefix +
        "val tmp = byTemplate\n" +
        "                if (tmp != null) {\n" +
        "                    ansTexts[i-1] = tmp; readCount++; done(); continue\n" +
        "                }\n"
    )

new_src, n = pattern.subn(repl, src, count=1)

if n == 0:
    new_src = src.replace(
        "if (byTemplate != null) {\n                    ansTexts[i-1] = byTemplate; readCount++; done(); continue\n                }",
        "val tmp = byTemplate\n                if (tmp != null) {\n                    ansTexts[i-1] = tmp; readCount++; done(); continue\n                }"
    )

    if new_src == src:
        print("[!] Patch did not match any location. Please check file context.", file=sys.stderr)
        sys.exit(2)

Path(sys.argv[1]).write_text(new_src, encoding="utf-8")
print("[+] Applied smart-cast fix in AutoMathAccessibilityService.kt")
PY

echo "==> Building..."
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
