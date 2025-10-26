set -euo pipefail

cd /workspaces/Auto-Math-OCR

echo "== backup =="
TS=$(date +%Y%m%d_%H%M%S)
BK=".backup_minpatch_$TS"
mkdir -p "$BK"

echo "== find MainActivity =="
MA_FILE="$(grep -RIl --include="*.kt" 'class MainActivity' app/src/main/java || true)"
if [ -z "${MA_FILE:-}" ]; then
echo "❌ لم أعثر على MainActivity.kt"; exit 1
fi
cp -a "$MA_FILE" "$BK/"

echo "== add dimens for fixed height (200dp) =="
mkdir -p app/src/main/res/values
if [ ! -f app/src/main/res/values/dimens.xml ] || ! grep -q 'black_box_height' app/src/main/res/values/dimens.xml; then
cat > app/src/main/res/values/dimens.xml <<'XML'
<resources>
<dimen name="black_box_height">200dp</dimen>
</resources>
XML
fi

echo "== patch MainActivity imports/properties/onCreate =="
for imp in \
'android.net.Uri' \
'android.widget.Button' \
'android.widget.ImageView' \
'android.widget.TextView' \
'android.widget.Toast' \
'android.text.method.ScrollingMovementMethod' \
'androidx.activity.result.contract.ActivityResultContracts' \
'com.fares.automathocr.R'; do
grep -qE "import[[:space:]]+$imp" "$MA_FILE" || \
sed -i "1,/^package /! s/^package .*/&\nimport $imp/" "$MA_FILE"
done

grep -q 'lateinit var previewImage' "$MA_FILE" || \
sed -i '/class MainActivity[^{]{/a \ \ \ \ private var previewImage: ImageView? = null' "$MA_FILE"
grep -q 'lateinit var blackBoxText' "$MA_FILE" || \
sed -i '/class MainActivity[^{]{/a \ \ \ \ private var blackBoxText: TextView? = null' "$MA_FILE"

if ! grep -q 'MINPATCH_BEGIN' "$MA_FILE"; then
sed -i '/setContentView(.)/a \
/ MINPATCH_BEGIN /\n\
run {\n\
val btnNames = listOf(\n\
"btnUpload","btnImport","btnPick","btnImage","pickImage","upload","btnSelectImage"\n\
)\n\
val imgNames = listOf(\n\
"previewImage","imagePreview","imageView","imgPreview"\n\
)\n\
val textNames = listOf(\n\
"blackBoxText","resultText","statusText","consoleText","ocrText","outputText"\n\
)\n\
fun idOf(name: String, type: String) = resources.getIdentifier(name, type, packageName)\n\
val btnId = btnNames.map { idOf(it, "id") }.firstOrNull { it != 0 } ?: 0\n\
val imgId = imgNames.map { idOf(it, "id") }.firstOrNull { it != 0 } ?: 0\n\
val txtId = textNames.map { idOf(it, "id") }.firstOrNull { it != 0 } ?: 0\n\
\n\
previewImage = if (imgId != 0) findViewById(imgId) else null\n\
blackBoxText = if (txtId != 0) findViewById(txtId) else null\n\
\n\
// ثبّت ارتفاع صندوق النص وخليه Scrollable لو موجود\n\
blackBoxText?.apply {\n\
isVerticalScrollBarEnabled = true\n\
movementMethod = ScrollingMovementMethod()\n\
val lp = layoutParams\n\
val h = resources.getDimensionPixelSize(R.dimen.black_box_height)\n\
if (lp != null && h > 0) { lp.height = h; layoutParams = lp }\n\
}\n\
\n\
// مُطلق لاختيار صورة من الجهاز\n\
val pickImageLauncher = registerForActivityResult(\n\
ActivityResultContracts.GetContent()\n\
) { uri: Uri? ->\n\
if (uri != null) {\n\
previewImage?.setImageURI(uri)\n\
blackBoxText?.text = "تم اختيار الصورة بنجاح ✅"\n\
if (previewImage == null) {\n\
Toast.makeText(this@MainActivity, "تم اختيار الصورة (لا يوجد ImageView للمعاينة)", Toast.LENGTH_SHORT).show()\n\
}\n\
} else {\n\
Toast.makeText(this@MainActivity, "لم يتم اختيار أي صورة", Toast.LENGTH_SHORT).show()\n\
}\n\
}\n\
\n\
// وصّل زر الرفع لو موجود\n\
if (btnId != 0) {\n\
val btn = findViewById<Button>(btnId)\n\
btn.setOnClickListener { pickImageLauncher.launch("image/") }\n\
}\n\
}\n\
/* MINPATCH_END */' "$MA_FILE"
fi

echo "== ensure theme + deps =="
if [ -f app/build.gradle ]; then
grep -q 'com.google.android.material:material' app/build.gradle || \
sed -i '/dependencies[[:space:]]{/a \    implementation "com.google.android.material:material:1.12.0"' app/build.gradle
grep -q 'androidx.constraintlayout:constraintlayout' app/build.gradle || \
sed -i '/dependencies[[:space:]]{/a \    implementation "androidx.constraintlayout:constraintlayout:2.1.4"' app/build.gradle
fi
if [ -f app/build.gradle.kts ]; then
grep -q 'com.google.android.material:material' app/build.gradle.kts || \
sed -i '/dependencies[[:space:]]{/a \    implementation("com.google.android.material:material:1.12.0")' app/build.gradle.kts
grep -q 'androidx.constraintlayout:constraintlayout' app/build.gradle.kts || \
sed -i '/dependencies[[:space:]]{/a \    implementation("androidx.constraintlayout:constraintlayout:2.1.4")' app/build.gradle.kts
fi

echo "== build =="
./gradlew --no-daemon assembleDebug

mkdir -p BuildOut
cp app/build/outputs/apk/debug/app-debug.apk BuildOut/AutoMathOCR-Patched.apk 2>/dev/null || true
ls -lh BuildOut || true
echo "✅ Done"
