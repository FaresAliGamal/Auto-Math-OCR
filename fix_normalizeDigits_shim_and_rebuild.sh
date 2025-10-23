set -euo pipefail

TEMPL="app/src/main/java/com/math/app/TemplateOcr.kt"
if [ ! -f "$TEMPL" ]; then
  echo "[!] لم يتم العثور على $TEMPL" >&2
  exit 1
fi

echo "[*] نسخ احتياطي -> TemplateOcr.kt.bak"
cp "$TEMPL" "$TEMPL.bak"

python3 - "$TEMPL" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

if "fun normalizeDigits(" not in s:
    idx = s.rfind("}")
    if idx == -1:
        print("[!] ملف TemplateOcr.kt غير متوازن الأقواس", file=sys.stderr)
        sys.exit(2)
    shim = """

    // --- shim للحفاظ على التوافق مع النداءات القديمة ---
    // بعض الأجزاء تنادي normalizeDigits؛ نعيد توجيهها إلى normalizeGlyph.
    fun normalizeDigits(bmp: android.graphics.Bitmap): android.graphics.Bitmap? {
        return normalizeGlyph(bmp)
    }
"""
    s = s[:idx] + shim + "\n}\n"
    p.write_text(s, encoding="utf-8")
    print("[+] تمت إضافة normalizeDigits shim")
else:
    print("[=] normalizeDigits موجودة بالفعل - لا تعديل")
PY

echo "[*] إعادة البناء..."
./gradlew assembleDebug --no-daemon

echo "[*] APKs:"
ls -lh app/build/outputs/apk/debug/ || true
