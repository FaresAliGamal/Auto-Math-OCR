set -euo pipefail

ROOT_DIR="$(pwd)"
MANIFEST="app/src/main/AndroidManifest.xml"
MAINACT="app/src/main/java/com/math/app/MainActivity.kt"

echo "==> Step 1/4: Ensure SYSTEM_ALERT_WINDOW permission in AndroidManifest.xml"
if ! grep -q 'android.permission.SYSTEM_ALERT_WINDOW' "$MANIFEST"; then
  awk '
    NR==1 && $0 ~ /<manifest/ {
      print;
      print "    <uses-permission android:name=\"android.permission.SYSTEM_ALERT_WINDOW\" />";
      next
    }
    { print }
  ' "$MANIFEST" > /tmp/AndroidManifest.xml
  mv /tmp/AndroidManifest.xml "$MANIFEST"
  echo "   [+] Added SYSTEM_ALERT_WINDOW permission."
else
  echo "   [=] Permission already present."
fi

echo "==> Step 2/4: Ensure imports & ensureOverlayPermission() exist in MainActivity.kt"

if ! grep -qE '^import[[:space:]]+android\.net\.Uri' "$MAINACT"; then
  awk '
    NR==1 { print; next }
    NR==2 && $0 ~ /^import/ {
      print "import android.net.Uri"
      print "import android.provider.Settings"
      print "import android.widget.Toast"
    }
    { print }
  ' "$MAINACT" > /tmp/MainActivity.kt.addimports
  mv /tmp/MainActivity.kt.addimports "$MAINACT"
  echo "   [+] Added imports for Uri, Settings, Toast."
else
   grep -q 'android.provider.Settings' "$MAINACT" || sed -i '2a import android.provider.Settings' "$MAINACT"
  grep -q 'android.widget.Toast'     "$MAINACT" || sed -i '2a import android.widget.Toast' "$MAINACT"
  echo "   [=] Required imports already present."
fi

if ! grep -q 'fun ensureOverlayPermission' "$MAINACT"; then
  awk '
    BEGIN { added=0 }
    {
      if (!added && $0 ~ /^}/) {
        print ""
        print "    private fun ensureOverlayPermission() {"
        print "        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M &&"
        print "            !android.provider.Settings.canDrawOverlays(this)) {"
        print "            Toast.makeText(this, \"فعّل إذن العرض فوق التطبيقات لمشاهدة السجل العائم\", Toast.LENGTH_LONG).show()"
        print "            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse(\"package:\" + packageName)))"
        print "        } else {"
        print "            try { OverlayLog.show(this) } catch (_: Exception) {}"
        print "        }"
        print "    }"
        print ""
        added=1
      }
      print
    }
  ' "$MAINACT" > /tmp/MainActivity.kt.ensurefunc
  mv /tmp/MainActivity.kt.ensurefunc "$MAINACT"
  echo "   [+] Added ensureOverlayPermission() function."
else
  echo "   [=] ensureOverlayPermission() already exists."
fi

if ! grep -q 'ensureOverlayPermission()' "$MAINACT"; then
  awk '
    BEGIN { inserted=0; inOnCreate=0 }
    {
      line=$0
      # detect onCreate start
      if ($0 ~ /override fun onCreate\(.*\)\s*{/) { inOnCreate=1 }
      # after setContentView(...) inside onCreate, insert call once
      if (inOnCreate==1 && inserted==0 && $0 ~ /setContentView\s*\(/) {
        print line
        print "        ensureOverlayPermission()"
        inserted=1
        next
      }
      # detect end of onCreate
      if (inOnCreate==1 && $0 ~ /^}/) { inOnCreate=0 }
      print line
    }
  ' "$MAINACT" > /tmp/MainActivity.kt.call
  mv /tmp/MainActivity.kt.call "$MAINACT"
  echo "   [+] Added ensureOverlayPermission() call in onCreate()."
else
  echo "   [=] ensureOverlayPermission() call already present."
fi

echo "==> Step 3/4: Quick confirmation"
grep -n 'SYSTEM_ALERT_WINDOW' "$MANIFEST" || true
grep -n 'ensureOverlayPermission' "$MAINACT" || true

echo "==> Step 4/4: Build APK (debug)"
./gradlew --no-daemon assembleDebug

echo "==> Done. APKs:"
ls -lh app/build/outputs/apk/debug/
