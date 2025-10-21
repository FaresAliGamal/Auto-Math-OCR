set -euo pipefail

cat > app/src/main/java/com/math/app/ScreenCaptureService.kt <<'KOT'
package com.math.app

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class ScreenCaptureService : Service() {

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        private const val CH_ID = "capture"
        private const val NOTI_ID = 1001
        private const val TAG = "ScreenCaptureService"
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CH_ID, "Screen Capture", NotificationManager.IMPORTANCE_LOW)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }

        // Action: تشغيل يدوي (يبعت برودكاست للخدمة)
        val runIntent = Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT).apply {
            putExtra("target", "")
        }
        val runPending = PendingIntent.getBroadcast(
            this, 1, runIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val noti = NotificationCompat.Builder(this, CH_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("التقاط الشاشة قيد التشغيل")
            .setContentText("اضغط \"تشغيل يدوي\" للمحاولة فورًا")
            .addAction(0, "تشغيل يدوي", runPending)
            .setOngoing(true)
            .build()

        startForeground(NOTI_ID, noti)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val code = intent?.getIntExtra(EXTRA_CODE, Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED

        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_DATA)
        }

        if (code == Activity.RESULT_OK && data != null) {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = mpm.getMediaProjection(code, data)
            ScreenGrabber.setProjection(mp)
            Log.d(TAG, "MediaProjection set ✔️")
        } else {
            Log.w(TAG, "MediaProjection data missing/denied")
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
KOT

cat > app/src/main/java/com/math/app/ScreenGrabber.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager

object ScreenGrabber {
    private const val TAG = "ScreenGrabber"
    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null

    fun setProjection(mp: MediaProjection) {
        mediaProjection = mp
    }

    fun hasProjection(): Boolean = mediaProjection != null

    fun capture(ctx: Context): Bitmap? {
        val mp = mediaProjection ?: run {
            Log.w(TAG, "capture(): mediaProjection == null")
            return null
        }
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        val width = dm.widthPixels
        val height = dm.heightPixels
        val dpi = dm.densityDpi

        if (imageReader == null) {
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            Log.d(TAG, "ImageReader created ${width}x${height}")
        }
        if (virtualDisplay == null) {
            virtualDisplay = mp.createVirtualDisplay(
                "ocr-vd", width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,
                imageReader!!.surface, null, null
            )
            Log.d(TAG, "VirtualDisplay created")
        }

        val img = imageReader!!.acquireLatestImage() ?: run {
            Thread.sleep(120)
            imageReader!!.acquireLatestImage()
        } ?: run {
            Log.w(TAG, "No image frame yet")
            return null
        }

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

cat > app/src/main/java/com/math/app/AutoMathAccessibilityService.kt <<'KOT'
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
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast

class AutoMathAccessibilityService : AccessibilityService() {

    companion object {
        const val ACTION_TAP_TEXT = "com.math.app.ACTION_TAP_TEXT"
        private const val TAG = "AutoMathService"

        fun isEnabled(ctx: Context): Boolean {
            val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            if (!am.isEnabled) return false
            val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = "${ctx.packageName}/${AutoMathAccessibilityService::class.java.name}"
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }
    }

    private var lastRunMs = 0L
    private val COOL_DOWN = 700L

    private val manualTrigger = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        registerReceiver(manualTrigger, IntentFilter(ACTION_TAP_TEXT))
        Toast.makeText(this, "خدمة الوصول فعّالة ✔️", Toast.LENGTH_SHORT).show()
        Log.d(TAG, "Service connected")
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

        if (!ScreenGrabber.hasProjection()) {
            Toast.makeText(this, "⚠️ التقاط الشاشة غير مفعّل", Toast.LENGTH_SHORT).show()
            Log.w(TAG, "Projection OFF")
            return
        }

        if (!optionalText.isNullOrBlank() && tryTapByNode(optionalText)) {
            Toast.makeText(this, "نقر \"$optionalText\" من الشجرة", Toast.LENGTH_SHORT).show()
            Log.d(TAG, "Tapped node by text: $optionalText")
            return
        }

        val bmp = ScreenGrabber.capture(this)
        if (bmp == null) {
            Toast.makeText(this, "لم أستطع التقاط لقطة شاشة", Toast.LENGTH_SHORT).show()
            Log.w(TAG, "capture() returned null")
            return
        }

        OcrHelper.recognize(this, bmp, { text ->
            if (!optionalText.isNullOrBlank()) {
                val t = OcrHelper.detectLines(text).firstOrNull {
                    MathSolver.normalizeDigits(it.text).contains(MathSolver.normalizeDigits(optionalText))
                }?.box
                if (t != null) { tapCenter(t); Toast.makeText(this, "نقر \"$optionalText\" بالـ OCR", Toast.LENGTH_SHORT).show(); return@recognize }
            }

            val lines = OcrHelper.detectLines(text)
            val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }
            if (eqLine == null) {
                Toast.makeText(this, "لم أجد معادلة واضحة", Toast.LENGTH_SHORT).show()
                Log.d(TAG, "No equation-like line found")
                return@recognize
            }

            val equationRaw = eqLine.text.replace("＝","=").replace(" ", "")
            val result = MathSolver.solveEquation(equationRaw)
            if (result == null) {
                Toast.makeText(this, "تعذر حل: $equationRaw", Toast.LENGTH_SHORT).show()
                Log.d(TAG, "Cannot solve: $equationRaw")
                return@recognize
            }

            val choices = OcrHelper.detectNumericChoices(text)
            val target = choices.firstOrNull { MathSolver.normalizeDigits(it.text) == result.toString() }
            if (target == null) {
                Toast.makeText(this, "النتيجة $result غير موجودة ضمن الاختيارات", Toast.LENGTH_SHORT).show()
                Log.d(TAG, "Answer $result not found in choices")
                return@recognize
            }

            tapCenter(target.box)
            Toast.makeText(this, "تم النقر: $result", Toast.LENGTH_SHORT).show()
            Log.d(TAG, "Tapped answer: $result at ${target.box}")
        }, {
            Toast.makeText(this, "فشل OCR", Toast.LENGTH_SHORT).show()
            Log.e(TAG, "OCR failure", it)
        })
    }

    private fun tapCenter(r: RectF) {
        val cx = (r.left + r.right) / 2f
        val cy = (r.top + r.bottom) / 2f
        val path = Path().apply { moveTo(cx, cy) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 90)
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

./gradlew --no-daemon clean assembleDebug
