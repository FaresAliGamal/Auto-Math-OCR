set -euo pipefail

REPO_ROOT="$(pwd)"
echo "==> Patching project to use a Foreground Service for MediaProjection (Android 14)"

cat > "$REPO_ROOT/app/src/main/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

<!-- لازمة من Android 14 لتشغيل MediaProjection داخل Foreground Service -->  
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>  

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

    <!-- خدمة الوصول (كما كانت) -->  
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

    <!-- خدمة أمامية خاصة بالتقاط الشاشة لنظام Android 14+ -->  
    <service  
        android:name=".ScreenCaptureService"  
        android:exported="false"  
        android:foregroundServiceType="mediaProjection" />  

</application>

</manifest>  
MANIFEST  mkdir -p "$REPO_ROOT/app/src/main/java/com/math/app"
cat > "$REPO_ROOT/app/src/main/java/com/math/app/ScreenCaptureService.kt" <<'KOT'
package com.math.app

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ScreenCaptureService : Service() {

companion object {  
    const val EXTRA_CODE = "code"  
    const val EXTRA_DATA = "data"  
    private const val CH_ID = "capture"  
    private const val NOTI_ID = 1001  
}  

override fun onCreate() {  
    super.onCreate()  
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {  
        val ch = NotificationChannel(CH_ID, "Screen Capture", NotificationManager.IMPORTANCE_LOW)  
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)  
            .createNotificationChannel(ch)  
    }  
    val noti = NotificationCompat.Builder(this, CH_ID)  
        .setSmallIcon(android.R.drawable.stat_sys_screenshot)  
        .setContentTitle("التقاط الشاشة قيد التشغيل")  
        .setContentText("خدمة أمامية مطلوبة من النظام")  
        .setOngoing(true)  
        .build()  
    startForeground(NOTI_ID, noti)  
}  

override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {  
    val code = intent?.getIntExtra(EXTRA_CODE, Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED  
    val data = intent?.getParcelableExtra<Intent>(EXTRA_DATA)  
    if (code == Activity.RESULT_OK && data != null) {  
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager  
        val mp = mpm.getMediaProjection(code, data)  
        ScreenGrabber.setProjection(mp)  
    }  
    return START_STICKY  
}  

override fun onBind(intent: Intent?): IBinder? = null

}
KOT

cat > "$REPO_ROOT/app/src/main/java/com/math/app/ScreenGrabber.kt" <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
import android.view.WindowManager

object ScreenGrabber {
private var mediaProjection: MediaProjection? = null
private var imageReader: ImageReader? = null
private var virtualDisplay: VirtualDisplay? = null

fun setProjection(mp: MediaProjection) {  
    mediaProjection = mp  
}  

fun capture(ctx: Context): Bitmap? {  
    val mp = mediaProjection ?: return null  
    val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager  
    val dm = DisplayMetrics()  
    @Suppress("DEPRECATION")  
    wm.defaultDisplay.getRealMetrics(dm)  
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
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
private lateinit var status: TextView
private lateinit var targetInput: EditText

private val captureLauncher = registerForActivityResult(  
    ActivityResultContracts.StartActivityForResult()  
) { result ->  
    if (result.resultCode == Activity.RESULT_OK && result.data != null) {  
        val svc = Intent(this, ScreenCaptureService::class.java).apply {  
            putExtra(ScreenCaptureService.EXTRA_CODE, result.resultCode)  
            putExtra(ScreenCaptureService.EXTRA_DATA, result.data)  
        }  
        ContextCompat.startForegroundService(this, svc)  
        status.text = "تم تفعيل التقاط الشاشة ✅"  
    } else {  
        status.text = "تم رفض إذن التقاط الشاشة ❌"  
    }  
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
        val i = Intent(AutoMathAccessibilityService.Companion.ACTION_TAP_TEXT)  
        i.putExtra("target", targetInput.text.toString())  
        sendBroadcast(i)  
        status.text = "جارٍ التشغيل…"  
    }  
}

}
KOT

cat > "$REPO_ROOT/app/src/main/res/xml/accessibility_service_config.xml" <<'ACCXML'
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"  
android:accessibilityEventTypes="typeWindowContentChanged|typeViewClicked|typeWindowStateChanged"  
android:accessibilityFeedbackType="feedbackGeneric"  
android:notificationTimeout="50"  
android:canRetrieveWindowContent="true"  
android:accessibilityFlags="flagReportViewIds|flagRetrieveInteractiveWindows"  
android:description="@string/acc_desc" />
ACCXML

echo "==> Building APK..."
cd "$REPO_ROOT"
./gradlew --no-daemon clean assembleDebug

echo "==> Done. APKs:"
ls -lh app/build/outputs/apk/debug/
