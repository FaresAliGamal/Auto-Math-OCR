set -euo pipefail

MANIFEST="app/src/main/AndroidManifest.xml"

if [ ! -f "$MANIFEST" ]; then
  echo "[!] لم يتم العثور على $MANIFEST" >&2
  exit 1
fi

echo "[*] Backup manifest -> AndroidManifest.xml.bak2"
cp "$MANIFEST" "$MANIFEST.bak2"

python3 - "$MANIFEST" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")

def ensure_perm(src, perm):
    if f'android:name="{perm}"' in src: 
        return src
    return re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="%s"/>' % perm, src, count=1)

t = ensure_perm(t, "android.permission.READ_EXTERNAL_STORAGE")  
t = ensure_perm(t, "android.permission.READ_MEDIA_IMAGES")
if 'requestLegacyExternalStorage="true"' not in t:
    t = re.sub(r'(<application\b[^>]*?)>',
               r'\1 android:requestLegacyExternalStorage="true">', t, count=1)

Path(sys.argv[1]).write_text(t, encoding="utf-8")
print("[+] Manifest fixed OK")
PY

echo "[*] Clean & Rebuild..."
./gradlew clean --no-daemon || true
./gradlew assembleDebug --no-daemon

echo "[*] APKs:"
ls -lh app/build/outputs/apk/debug/ || true
