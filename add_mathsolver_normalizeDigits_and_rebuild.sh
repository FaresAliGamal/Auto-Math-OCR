set -euo pipefail

SOLVER="app/src/main/java/com/math/app/MathSolver.kt"
[ -f "$SOLVER" ] || { echo "[!] Missing $SOLVER"; exit 1; }

echo "[*] Backup -> MathSolver.kt.bak2"
cp "$SOLVER" "$SOLVER.bak2"

python3 - "$SOLVER" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

m = re.search(r'\bobject\s+MathSolver\s*\{', s)
if not m:
    print("[!] لم أجد object MathSolver {", file=sys.stderr); sys.exit(2)

if "fun normalizeDigits(" not in s:
    insert_at = s.rfind("}")
    shim = r"""

    // --- shim: normalizeDigits ---
    // تُحوّل الأرقام العربية/الفارسية إلى ASCII 0-9
    // وتوحّد الرموز: x * -> ×  ،  / -> ÷ ، وتزيل أي محارف أخرى.
    fun normalizeDigits(raw: String): String {
        if (raw.isEmpty()) return ""
        val out = StringBuilder()
        for (ch in raw) {
            when (ch) {
                // ASCII digits
                in '0'..'9' -> out.append(ch)

                // Arabic-Indic digits ٠..٩ (U+0660..U+0669)
                '٠' -> out.append('0'); '١' -> out.append('1'); '٢' -> out.append('2'); '٣' -> out.append('3'); '٤' -> out.append('4')
                '٥' -> out.append('5'); '٦' -> out.append('6'); '٧' -> out.append('7'); '٨' -> out.append('8'); '٩' -> out.append('9')

                // Extended Arabic-Indic (Persian) ۰..۹ (U+06F0..U+06F9)
                '۰' -> out.append('0'); '۱' -> out.append('1'); '۲' -> out.append('2'); '۳' -> out.append('3'); '۴' -> out.append('4')
                '۵' -> out.append('5'); '۶' -> out.append('6'); '۷' -> out.append('7'); '۸' -> out.append('8'); '۹' -> out.append('9')

                // Operators (normalize all to one set)
                '+', '-' -> out.append(ch)
                'x', 'X', '*', '×' -> out.append('×')
                '/', '÷' -> out.append('÷')

                // ignore everything else (spaces, punctuation, noise)
                else -> { /* skip */ }
            }
        }
        return out.toString()
    }
"""
    s = s[:insert_at] + shim + "\n}\n"

p.write_text(s, encoding="utf-8")
print("[+] MathSolver.normalizeDigits added/ensured")
PY

echo "[*] Rebuild..."
./gradlew assembleDebug --no-daemon

echo "[*] APKs:"
ls -lh app/build/outputs/apk/debug/ || true
