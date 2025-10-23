set -euo pipefail

SVC="app/src/main/java/com/math/app/AutoMathAccessibilityService.kt"
if [ -f "$SVC" ]; then
  python3 - "$SVC" <<'PY'
from pathlib import Path, re, sys
p = Path(sys.argv[1]); s = p.read_text(encoding="utf-8")

pat = re.compile(r"private fun runOnce\(optionalText: String\?\)\s*\{", re.S)
if pat.search(s) and "tryTapByNode(optionalText)" not in s:
    s = s.replace(
        "private fun runOnce(optionalText: String?) {",
        "private fun runOnce(optionalText: String?) {"
        "\n        // If a text/symbol was provided, try tapping it directly"
        "\n        if (optionalText != null) {"
        "\n            if (tryTapByNode(optionalText)) return"
        "\n        }"
    )

p.write_text(s, encoding="utf-8")
print("[+] Service: optionalText now triggers tryTapByNode()")
PY
else
  echo "[!] Service file not found: $SVC" >&2
fi

LAY="app/src/main/res/layout/activity_main.xml"
if [ -f "$LAY" ]; then
  python3 - "$LAY" <<'PY'
from pathlib import Path, re, sys
p = Path(sys.argv[1]); x = p.read_text(encoding="utf-8")

block_symbols = '''
    <!-- Symbols row -->
    <LinearLayout
        android:id="@+id/rowSymbols"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center"
        android:paddingTop="8dp"
        android:paddingBottom="8dp">

        <Button
            android:id="@+id/btnPlus"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="+"/>

        <Button
            android:id="@+id/btnMinus"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="-"/>

        <Button
            android:id="@+id/btnTimes"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="×"/>

        <Button
            android:id="@+id/btnDivide"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="÷"/>
    </LinearLayout>
'''.strip()

block_tools = '''
    <!-- Tools row -->
    <LinearLayout
        android:id="@+id/rowTools"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center"
        android:paddingTop="4dp"
        android:paddingBottom="8dp">

        <Button
            android:id="@+id/btnRegions"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Regions"/>

        <Button
            android:id="@+id/btnTemplates"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="Templates"/>
    </LinearLayout>
'''.strip()

if 'android:id="@+id/btnPlus"' not in x:
    x = re.sub(r"\n\s*</(\w+)\s*>\s*$", "\n\n" + block_symbols + "\n\n" + block_tools + "\n</\\1>\n", x, flags=re.S)

p.write_text(x, encoding="utf-8")
print("[+] Layout: added symbol buttons and Regions/Templates buttons")
PY
else
  echo "[!] Layout not found: $LAY" >&2
fi

ACT="app/src/main/java/com/math/app/MainActivity.kt"
if [ -f "$ACT" ]; then
  python3 - "$ACT" <<'PY'
from pathlib import Path, re, sys
p = Path(sys.argv[1]); s = p.read_text(encoding="utf-8")

if "import android.widget.Button" not in s:
    s = s.replace("import android.os.Bundle", "import android.os.Bundle\nimport android.widget.Button")
if "import android.content.Intent" not in s:
    s = s.replace("import android.os.Bundle", "import android.os.Bundle\nimport android.content.Intent")
if "import androidx.appcompat.app.AlertDialog" not in s:
    s = s.replace("import androidx.appcompat.app.AppCompatActivity", "import androidx.appcompat.app.AppCompatActivity\nimport androidx.appcompat.app.AlertDialog")

idx = s.find("override fun onCreate")
if idx == -1:
    print("[!] onCreate() not found", file=sys.stderr); sys.exit(1)
br = s.find("{", idx)
depth=1; i=br+1
while i < len(s) and depth>0:
    if s[i] == '{': depth += 1
    elif s[i] == '}': depth -= 1
    i += 1
body = s[br+1:i-1]

inject_handlers = '''
        // --- Regions editor button (replaces long-press)
        findViewById<Button>(R.id.btnRegions).setOnClickListener {
            try { OverlayRegions.toggle(this) } catch (_: Exception) {}
        }

        // --- Templates button: dialog to save a digit template from a region
        findViewById<Button>(R.id.btnTemplates).setOnClickListener {
            val ctx = this
            val edRegion = android.widget.EditText(ctx).apply {
                hint = "region 0..4 (0=Q)"; inputType = android.text.InputType.TYPE_CLASS_NUMBER
            }
            val edDigit  = android.widget.EditText(ctx).apply {
                hint = "digit 0..9"; inputType = android.text.InputType.TYPE_CLASS_NUMBER
            }
            val lay = android.widget.LinearLayout(ctx).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                setPadding(48,24,48,0)
                addView(edRegion); addView(edDigit)
            }
            AlertDialog.Builder(ctx)
                .setTitle("Save digit template")
                .setView(lay)
                .setPositiveButton("Save") { _, _ ->
                    val r = edRegion.text.toString().toIntOrNull()
                    val d = edDigit.text.toString().toIntOrNull()
                    if (r==null || d==null) {
                        android.widget.Toast.makeText(ctx, "Enter valid numbers", android.widget.Toast.LENGTH_SHORT).show()
                    } else {
                        sendBroadcast(Intent(com.math.app.AutoMathAccessibilityService.ACTION_SAVE_TEMPLATE)
                            .putExtra("region", r).putExtra("digit", d))
                    }
                }
                .setNegativeButton("Cancel", null)
                .show()
        }

        // --- Symbol buttons (+ - × ÷) -> Broadcast to service to try tapping the symbol
        findViewById<Button>(R.id.btnPlus).setOnClickListener {
            sendBroadcast(Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT).putExtra("target", "+"))
        }
        findViewById<Button>(R.id.btnMinus).setOnClickListener {
            sendBroadcast(Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT).putExtra("target", "-"))
        }
        findViewById<Button>(R.id.btnTimes).setOnClickListener {
            sendBroadcast(Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT).putExtra("target", "×"))
        }
        findViewById<Button>(R.id.btnDivide).setOnClickListener {
            sendBroadcast(Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT).putExtra("target", "÷"))
        }
'''.rstrip()

need = any(id not in body for id in ["btnRegions", "btnTemplates", "btnPlus", "btnMinus", "btnTimes", "btnDivide"])
if need:
    body = body + "\n" + inject_handlers + "\n"
    s = s[:br+1] + body + s[i-1:]
    p.write_text(s, encoding="utf-8")
    print("[+] MainActivity: wired Regions/Templates & symbol buttons")
else:
    print("[=] MainActivity already wired")
PY
else
  echo "[!] MainActivity not found: $ACT" >&2
fi

echo "==> Building debug APK…"
./gradlew --no-daemon assembleDebug

echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
