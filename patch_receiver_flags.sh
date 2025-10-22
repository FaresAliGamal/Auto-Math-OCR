set -euo pipefail

cat > app/src/main/java/com/math/app/MainActivity.kt <<'KOT'
package com.math.app

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    private lateinit var status: TextView
    private lateinit var targetInput: EditText
    private val uiHandler = Handler(Looper.getMainLooper())

    // نتيجة التقاط الشاشة
    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            requestNotifPermissionIfNeeded()

            val svcIntent = Intent(this, ScreenCaptureService::class.java).apply {
                putExtra(ScreenCaptureService.EXTRA_CODE, result.resultCode)
                putExtra(ScreenCaptureService.EXTRA_DATA, result.data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, svcIntent)
            } else {
                startService(svcIntent)
            }
            status.text = "تم تفعيل التقاط الشاشة بنجاح ✅"
        } else {
            status.text = "تم رفض إذن التقاط الشاشة ❌"
        }
        refreshIndicators()
    }

    // Receiver من الخدمة لتأكيد حالة إمكانية الوصول
    private val accStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AutoMathAccessibilityService.ACTION_ACC_STATUS) {
                refreshIndicators()
            }
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
            val i = Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT)
            i.putExtra("target", targetInput.text.toString())
            sendBroadcast(i)
            status.text = "جارٍ التشغيل…"
        }

        // اطلب إذن الإشعارات مرة واحدة عند فتح التطبيق
        requestNotifPermissionIfNeeded()
        refreshIndicators()
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(AutoMathAccessibilityService.ACTION_ACC_STATUS)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(accStatusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(accStatusReceiver, filter)
        }
        // كمان حدّث الحالة كل ثانية كاحتياط
        uiHandler.post(object : Runnable {
            override fun run() {
                refreshIndicators()
                uiHandler.postDelayed(this, 1000)
            }
        })
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(accStatusReceiver) } catch (_: Exception) {}
        uiHandler.removeCallbacksAndMessages(null)
    }

    private fun refreshIndicators() {
        val proj = if (ScreenGrabber.hasProjection()) "✅ التقاط الشاشة" else "⬜ التقاط الشاشة"
        val acc  = if (AutoMathAccessibilityService.isEnabled(this)) "✅ خدمة الوصول" else "❌ خدمة الوصول"
        status.text = "$proj   |   $acc"
    }

    private fun requestNotifPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val nm = NotificationManagerCompat.from(this)
            if (!nm.areNotificationsEnabled()) {
                registerForActivityResult(ActivityResultContracts.RequestPermission()) {}.launch(
                    Manifest.permission.POST_NOTIFICATIONS
                )
            }
        }
    }
}
KOT

cat > app/src/main/java/com/math/app/AutoMathAccessibilityService.kt <<'KOT'
package com.math.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
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
        const val ACTION_ACC_STATUS = "com.math.app.ACTION_ACC_STATUS"
        private const val TAG = "AutoMathService"

        fun isEnabled(ctx: Context): Boolean {
            val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
            val list = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            val myPkg = ctx.packageName
            val myCls = AutoMathAccessibilityService::class.java.name
            for (info in list) {
                val si = info.resolveInfo?.serviceInfo ?: continue
                if (si.packageName == myPkg && si.name == myCls) return true
            }
            val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = "$myPkg/$myCls"
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }
    }

    private var lastRunMs = 0L
    private val COOL_DOWN = 700L

    private val manualTrigger = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        val filter = IntentFilter(ACTION_TAP_TEXT)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(manualTrigger, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(manualTrigger, filter)
        }
        sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", true))
        Toast.makeText(this, "خدمة الوصول فعّالة ✔️", Toast.LENGTH_SHORT).show()
        Log.d(TAG, "Service connected")
    }

    override fun onDestroy() {
        super.onDestroy()
        sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", false))
        try { unregisterReceiver(manualTrigger) } catch (_: Exception) {}
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

        val bmp = ScreenGrabber.capture(this) ?: run {
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
            val result = MathSolver.solveEquation(equationRaw) ?: run {
                Toast.makeText(this, "تعذر حل: $equationRaw", Toast.LENGTH_SHORT).show()
                Log.d(TAG, "Cannot solve: $equationRaw")
                return@recognize
            }

            val choices = OcrHelper.detectNumericChoices(text)
            val target = choices.firstOrNull { MathSolver.normalizeDigits(it.text) == result.toString() } ?: run {
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

echo "==> Building..."
./gradlew --no-daemon clean assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
