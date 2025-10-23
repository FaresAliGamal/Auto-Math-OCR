set -euo pipefail

MANIFEST="app/src/main/AndroidManifest.xml"
MA="app/src/main/java/com/math/app/MainActivity.kt"

if [ ! -f "$MANIFEST" ]; then echo "[!] لا يوجد Manifest"; exit 1; fi
cp "$MANIFEST" "$MANIFEST.bak3"

python3 - "$MANIFEST" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")

def ensure_perm(src, perm):
    if f'android:name="{perm}"' in src: 
        return src
    return re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="%s"/>' % perm, src, count=1)

t = ensure_perm(t, "android.permission.SYSTEM_ALERT_WINDOW")
Path(sys.argv[1]).write_text(t, encoding="utf-8")
print("[+] Manifest: SYSTEM_ALERT_WINDOW ensured")
PY

if [ ! -f "$MA" ]; then echo "[!] لا يوجد MainActivity"; exit 1; fi
cp "$MA" "$MA.bak3"

python3 - "$MA" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

for imp in [
  "import android.provider.Settings",
  "import android.net.Uri",
  "import androidx.appcompat.app.AlertDialog",
]:
    if imp not in s:
        s = s.replace("import android.os.Bundle", "import android.os.Bundle\n"+imp)

if "private fun ensureOverlayPermission()" not in s:
    helper = '''
    private fun ensureOverlayPermission() {
        if (!Settings.canDrawOverlays(this)) {
            AlertDialog.Builder(this)
                .setTitle("السماح بالظهور فوق التطبيقات")
                .setMessage("لتصغير نافذة اللوج والتحكّم بها، فعّل صلاحية الظهور فوق التطبيقات.")
                .setPositiveButton("فتح الإعدادات") { _, _ ->
                    val uri = Uri.parse("package:$packageName")
                    val intent = android.content.Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri)
                    startActivity(intent)
                }
                .setNegativeButton("لاحقًا", null)
                .show()
        }
    }
    '''
    s = re.sub(r'(class\s+MainActivity[^{]*\{)', r'\1\n' + helper + "\n", s)

m = re.search(r'override\s+fun\s+onCreate\s*\([^)]*\)\s*\{', s)
if m:
    br = m.end(); depth=1; i=br
    while i < len(s) and depth>0:
        if s[i]=='{': depth+=1
        elif s[i]=='}': depth-=1
        i+=1
    body = s[br:i-1]
    if "ensureOverlayPermission()" not in body:
        body = body + "\n        // تأكد من صلاحية overlay\n        ensureOverlayPermission()\n"
        s = s[:br] + body + s[i-1:]

p.write_text(s, encoding="utf-8")
print("[+] MainActivity: overlay permission prompt injected")
PY

echo "[*] Clean & Rebuild..."
./gradlew clean --no-daemon || true
./gradlew assembleDebug --no-daemon

echo "[*] APKs:"
ls -lh app/build/outputs/apk/debug/ || true
