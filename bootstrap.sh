set -euo pipefail

echo "==> Auto setup: full app code + Android SDK + build"

REPO_ROOT="$(pwd)"

mkdir -p "$REPO_ROOT/app/src/main/java/com/math/app" \
         "$REPO_ROOT/app/src/main/res/layout" \
         "$REPO_ROOT/app/src/main/res/values" \
         "$REPO_ROOT/app/src/main/res/xml" \
         "$REPO_ROOT/app/src/main/res/mipmap-anydpi-v26"

cat > "$REPO_ROOT/settings.gradle" <<'SETTINGS'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "AutoMathTapper-OCR"
include(":app")
SETTINGS

cat > "$REPO_ROOT/build.gradle" <<'ROOTBUILD'
buildscript {
    dependencies {
        classpath "com.android.tools.build:gradle:8.6.0"
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24"
    }
}
ROOTBUILD

cat > "$REPO_ROOT/gradle.properties" <<'PROPS'
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
PROPS

cat > "$REPO_ROOT/app/build.gradle" <<'APPBUILD'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace "com.math.app"
    compileSdk 34

    defaultConfig {
        applicationId "com.math.app"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.13.1'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.android.material:material:1.12.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'com.google.mlkit:text-recognition:16.0.1'
}
APPBUILD

cat > "$REPO_ROOT/app/src/main/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="AutoMathTapper OCR"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="true"
        android:supportsRtl="true"
        android:theme="@style/Theme.Material3.DayNight.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <service
            android:name=".AutoMathAccessibilityService"
            android:exported="true"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config"/>
        </service>

    </application>
</manifest>
MANIFEST

cat > "$REPO_ROOT/app/src/main/res/xml/accessibility_service_config.xml" <<'ACCXML'
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowContentChanged|typeViewClicked|typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:notificationTimeout="50"
    android:canPerformGestures="true"
    android:flags="flagReportViewIds|flagRetrieveInteractiveWindows"
    android:description="@string/acc_desc"/>
ACCXML

cat > "$REPO_ROOT/app/src/main/res/layout/activity_main.xml" <<'LAYOUT'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="20dp"
    android:background="#FFEAE6">

    <TextView
        android:id="@+id/title"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:text="AutoMathTapper OCR"
        android:textSize="22sp"
        android:textStyle="bold"
        android:gravity="center"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintTop_toTopOf="parent"/>

    <EditText
        android:id="@+id/targetInput"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:hint="(اختياري) الكلمة للضغط عليها مباشرة"
        android:inputType="text"
        android:layout_marginTop="16dp"
        app:layout_constraintTop_toBottomOf="@id/title"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"/>

    <Button
        android:id="@+id/btnGrant"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:text="ابدأ • سماح التقاط الشاشة"
        android:layout_marginTop="12dp"
        app:layout_constraintTop_toBottomOf="@id/targetInput"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"/>

    <Button
        android:id="@+id/btnRun"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:text="تشغيل يدوي"
        android:layout_marginTop="12dp"
        app:layout_constraintTop_toBottomOf="@id/btnGrant"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"/>

    <TextView
        android:id="@+id/status"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:text="Ready."
        android:layout_marginTop="16dp"
        app:layout_constraintTop_toBottomOf="@id/btnRun"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"/>

</androidx.constraintlayout.widget.ConstraintLayout>
LAYOUT

cat > "$REPO_ROOT/app/src/main/res/values/strings.xml" <<'STRINGS'
<resources>
    <string name="app_name">AutoMathTapper OCR</string>
    <string name="acc_desc">خدمة وصول للنقر التلقائي باستخدام OCR</string>
</resources>
STRINGS

cat > "$REPO_ROOT/app/src/main/java/com/math/app/MainActivity.kt" <<'KOT'
package com.math.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var status: TextView
    private lateinit var targetInput: EditText

    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            ScreenGrabber.setProjection(this, result.resultCode, result.data!!)
            status.text = "تم منح إذن التقاط الشاشة ✅"
        } else status.text = "تم رفض إذن التقاط الشاشة ❌"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        status = findViewById(R.id.status)
        targetInput = findViewById(R.id.targetInput)

        findViewById<Button>(R.id.btnGrant).setOnClickListener {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            captureLauncher.launch(mpm.createScreenCaptureIntent())
        }
        findViewById<Button>(R.id.btnRun).setOnClickListener {
            val i = Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT)
            i.putExtra("target", targetInput.text.toString())
            sendBroadcast(i)
            status.text = "جارٍ التشغيل…"
        }
    }
}
KOT

cat > "$REPO_ROOT/app/src/main/java/com/math/app/ScreenGrabber.kt" <<'KOT'
package com.math.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.util.DisplayMetrics
import android.view.WindowManager

object ScreenGrabber {
    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null

    fun setProjection(ctx: Context, resultCode: Int, data: Intent) {
        val mpm = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data)
    }

    fun capture(ctx: Context): Bitmap? {
        val mp = mediaProjection ?: return null
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        val display = wm.defaultDisplay
        display.getRealMetrics(dm)
        val width = dm.widthPixels
        val height = dm.heightPixels
        val dpi = dm.densityDpi

        if (imageReader == null) {
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        }
        if (virtualDisplay == null) {
            virtualDisplay = mp.createVirtualDisplay(
                "ocr-vd", width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,
                imageReader!!.surface, null, null
            )
        }

        val img = imageReader!!.acquireLatestImage() ?: run {
            Thread.sleep(80)
            imageReader!!.acquireLatestImage()
        } ?: return null

        val plane = img.planes[0]
        val buf = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width
        val bmp = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888)
        bmp.copyPixelsFromBuffer(buf)
        img.close()
        return Bitmap.createBitmap(bmp, 0, 0, width, height)
    }
}
KOT

cat > "$REPO_ROOT/app/src/main/java/com/math/app/OcrHelper.kt" <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)

object OcrHelper {
    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    fun recognize(ctx: Context, bitmap: Bitmap,
                  onDone: (Text) -> Unit, onError: (Exception) -> Unit) {
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener(onDone)
            .addOnFailureListener(onError)
    }

    fun detectLines(t: Text): List<Detected> =
        t.textBlocks.flatMap { b ->
            b.lines.mapNotNull { line ->
                line.boundingBox?.let { Detected(line.text.trim(), RectF(it)) }
            }
        }

    fun detectNumericChoices(t: Text): List<Detected> =
        detectLines(t).filter { it.text.matches(Regex("^[\\d٠-٩]+$")) }
}
KOT

cat > "$REPO_ROOT/app/src/main/java/com/math/app/MathSolver.kt" <<'KOT'
package com.math.app

object MathSolver {

    private val arabicDigits = mapOf(
        '٠' to '0','١' to '1','٢' to '2','٣' to '3','٤' to '4',
        '٥' to '5','٦' to '6','٧' to '7','٨' to '8','٩' to '9'
    )
    fun normalizeDigits(s: String): String =
        s.map { arabicDigits[it] ?: it }.joinToString("")

    fun solveEquation(raw: String): Int? {
        val s = normalizeDigits(raw)
            .replace("\\s+".toRegex(), "")
            .replace('×','*').replace('x','*').replace('·','*')
            .replace('÷','/')

        val m = Regex("^(-?\\d+)([+\\-*/])(-?\\d+)=?$").find(s) ?: return null
        val a = m.groupValues[1].toLong()
        val op = m.groupValues[2][0]
        val b = m.groupValues[3].toLong()
        val r = when (op) {
            '+' -> a + b
            '-' -> a - b
            '*' -> a * b
            '/' -> if (b != 0L && a % b == 0L) a / b else return null
            else -> return null
        }
        return r.toInt()
    }
}
KOT

cat > "$REPO_ROOT/app/src/main/java/com/math/app/AutoMathAccessibilityService.kt" <<'KOT'
package com.math.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.graphics.RectF
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AutoMathAccessibilityService : AccessibilityService() {

    companion object {
        const val ACTION_TAP_TEXT = "com.math.app.ACTION_TAP_TEXT"
    }

    private var lastRunMs = 0L
    private val COOL_DOWN = 700L

    private val manualTrigger = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        registerReceiver(manualTrigger, IntentFilter(ACTION_TAP_TEXT))
    }

    override fun onInterrupt() {}
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            runOnce(null)
        }
    }

    private fun runOnce(optionalText: String?) {
        val now = SystemClock.uptimeMillis()
        if (now - lastRunMs < COOL_DOWN) return
        lastRunMs = now

        if (!optionalText.isNullOrBlank() && tryTapByNode(optionalText)) return

        val bmp = ScreenGrabber.capture(this) ?: return
        OcrHelper.recognize(this, bmp, { text ->
            if (!optionalText.isNullOrBlank()) {
                val t = OcrHelper.detectLines(text).firstOrNull {
                    MathSolver.normalizeDigits(it.text).contains(
                        MathSolver.normalizeDigits(optionalText)
                    )
                }?.box
                if (t != null) { tapCenter(t); return@recognize }
            }

            val lines = OcrHelper.detectLines(text)
            val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) } ?: return@recognize
            val equationRaw = eqLine.text.replace("＝","=").replace(" ", "")
            val result = MathSolver.solveEquation(equationRaw) ?: return@recognize

            val choices = OcrHelper.detectNumericChoices(text)
            val target = choices.firstOrNull {
                MathSolver.normalizeDigits(it.text) == result.toString()
            } ?: return@recognize

            tapCenter(target.box)
        }, { /* ignore */ })
    }

    private fun tapCenter(r: RectF) {
        val cx = (r.left + r.right) / 2f
        val cy = (r.top + r.bottom) / 2f
        val path = Path().apply { moveTo(cx, cy) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 60)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun tryTapByNode(query: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(query)
        for (n in nodes) if (tapNode(n)) return true
        return false
    }
    private fun tapNode(node: AccessibilityNodeInfo?): Boolean {
        var cur = node
        while (cur != null) {
            if (cur.isClickable) return cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            cur = cur.parent
        }
        return false
    }
}
KOT

export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
cd "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "latest" ]; then
  curl -L -o cmdtools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  mkdir -p latest
  unzip -q cmdtools.zip -d latest
  rm -f cmdtools.zip
fi

if [ -d "latest/cmdline-tools" ] && [ -d "latest/cmdline-tools/bin" ] && [ ! -d "latest/bin" ]; then
  mv latest/cmdline-tools/* latest/
  rmdir latest/cmdline-tools || true
fi

export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
chmod +x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" || true

yes | sdkmanager --licenses >/dev/null || true
yes | sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

cd "$REPO_ROOT"
echo "sdk.dir=$ANDROID_SDK_ROOT" > local.properties

if [ ! -f "./gradlew" ]; then
  gradle wrapper --gradle-version 8.7
fi
chmod +x ./gradlew

./gradlew --no-daemon clean assembleDebug

echo "==> APK output:"
ls -lh app/build/outputs/apk/debug/
