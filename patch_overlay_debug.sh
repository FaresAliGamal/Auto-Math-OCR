set -euo pipefail

if ! grep -q 'android.permission.SYSTEM_ALERT_WINDOW' app/src/main/AndroidManifest.xml; then
  awk '1; /<application>/{print "        <!-- للعرض فوق التطبيقات -->\n        <uses-permission android:name=\"android.permission.SYSTEM_ALERT_WINDOW\" />"}' app/src/main/AndroidManifest.xml > /tmp/AndroidManifest.xml && mv /tmp/AndroidManifest.xml app/src/main/AndroidManifest.xml
fi

cat > app/src/main/java/com/math/app/OverlayLog.kt <<'KOT'
package com.math.app

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.text.method.ScrollingMovementMethod
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.*

object OverlayLog {
    private var tv: TextView? = null
    private var wm: WindowManager? = null
    private val buf = ArrayDeque<String>()
    private val sdf = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())

    fun show(ctx: Context) {
        if (tv != null) return
        wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        tv = TextView(ctx).apply {
            textSize = 12f
            typeface = Typeface.MONOSPACE
            setPadding(12, 8, 12, 8)
            setBackgroundColor(0xAA000000.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            movementMethod = ScrollingMovementMethod()
            text = "OverlayLog started…\n"
        }
        val type = if (Build.VERSION.SDK_INT >= 26)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = 12; lp.y = 60
        wm?.addView(tv, lp)
        flush()
    }

    fun hide() {
        tv?.let { wm?.removeView(it) }
        tv = null
        wm = null
        buf.clear()
    }

    fun post(msg: String) {
        val line = "${sdf.format(Date())}  $msg"
        if (tv == null) {
            if (buf.size > 200) buf.removeFirst()
            buf.addLast(line)
        } else {
            tv?.append(line + "\n")
            val layout = tv?.layout
            if (layout != null) {
                val scrollAmount = layout.getLineTop(tv!!.lineCount) - tv!!.height
                if (scrollAmount > 0) tv?.scrollTo(0, scrollAmount) else tv?.scrollTo(0, 0)
            }
        }
    }

    private fun flush() { while (buf.isNotEmpty()) tv?.append(buf.removeFirst() + "\n") }
}
KOT

apply_main=$(cat <<'KOT'
package com.math.app

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    private lateinit var status: TextView
    private lateinit var targetInput: EditText
    private val uiHandler = Handler(Looper.getMainLooper())

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
            } else startService(svcIntent)
            status.text = "تم تفعيل التقاط الشاشة ✅"
        } else status.text = "تم رفض إذن التقاط الشاشة ❌"
        refreshIndicators()
    }

    private val accStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AutoMathAccessibilityService.ACTION_ACC_STATUS) refreshIndicators()
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

        requestNotifPermissionIfNeeded()
        ensureOverlayPermission()
        refreshIndicators()
    }

    override fun onResume() {
        super.onResume()
        registerReceiver(accStatusReceiver, IntentFilter(AutoMathAccessibilityService.ACTION_ACC_STATUS),
            if (Build.VERSION.SDK_INT >= 33) Context.RECEIVER_NOT_EXPORTED else null)
        uiHandler.post(object : Runnable {
            override fun run() { refreshIndicators(); uiHandler.postDelayed(this, 1000) }
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

    private fun ensureOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "فعّل إذن العرض فوق التطبيقات لمشاهدة سجل العمليات", Toast.LENGTH_LONG).show()
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"))
            startActivity(intent)
        }
    }
}
KOT
)
echo "$apply_main" > app/src/main/java/com/math/app/MainActivity.kt

apply_svc=$(cat <<'KOT'
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
    private val COOL_DOWN = 900L

    private val manualTrigger = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { runOnce(intent?.getStringExtra("target")) }
    }

    override fun onServiceConnected() {
        val filter = IntentFilter(ACTION_TAP_TEXT)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(manualTrigger, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(manualTrigger, filter)

        // جرّب عرض اللوحة لو الإذن متاح
        try { OverlayLog.show(this) } catch (_: Exception) {}
        OverlayLog.post("Service connected ✅")
        sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", true))
    }

    override fun onDestroy() {
        super.onDestroy()
        OverlayLog.post("Service destroyed ❌")
        sendBroadcast(Intent(ACTION_ACC_STATUS).putExtra("enabled", false))
        try { unregisterReceiver(manualTrigger) } catch (_: Exception) {}
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            OverlayLog.post("Window state changed: ${event.className}")
        }
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
            OverlayLog.post("Projection OFF ⚠️")
            Toast.makeText(this, "⚠️ التقاط الشاشة غير مفعّل", Toast.LENGTH_SHORT).show()
            return
        }

        if (!optionalText.isNullOrBlank() && tryTapByNode(optionalText)) {
            OverlayLog.post("Tapped node by text: \"$optionalText\"")
            Toast.makeText(this, "نقر \"$optionalText\" من الشجرة", Toast.LENGTH_SHORT).show()
            return
        }

        val bmp = ScreenGrabber.capture(this)
            ?: run { OverlayLog.post("capture() returned null"); return }

        OcrHelper.recognizeSmart(this, bmp, { payload ->
            val lines = OcrHelper.detectLines(payload.text)
            val choices = OcrHelper.detectNumericChoices(payload.text)

            OverlayLog.post("OCR lines: " + lines.take(3).joinToString(" | ") { it.text })
            OverlayLog.post("Choices: ${choices.map { it.text }}")

            if (!optionalText.isNullOrBlank()) {
                val box = lines.firstOrNull {
                    MathSolver.normalizeDigits(it.text).contains(MathSolver.normalizeDigits(optionalText))
                }?.box
                if (box != null) {
                    val mapped = OcrHelper.mapRectToScreen(box, payload.transform)
                    OverlayLog.post("Click by OCR text @ (${mapped.centerX().toInt()}, ${mapped.centerY().toInt()})")
                    tapCenter(mapped)
                    return@recognizeSmart
                }
            }

            val eqLine = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }
            val equationRaw = eqLine?.text?.replace("＝","=")?.replace(" ", "")
            if (equationRaw == null) {
                OverlayLog.post("No clear equation")
                Toast.makeText(this, "لا توجد معادلة واضحة", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }
            val result = MathSolver.solveEquation(equationRaw)
            OverlayLog.post("Equation: $equationRaw => $result")

            if (result == null) {
                Toast.makeText(this, "تعذر حل: $equationRaw", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }

            val target = choices.firstOrNull { MathSolver.normalizeDigits(it.text) == result.toString() }
            if (target == null) {
                OverlayLog.post("Answer $result not in choices")
                Toast.makeText(this, "النتيجة $result غير موجودة", Toast.LENGTH_SHORT).show()
                return@recognizeSmart
            }

            val mapped = OcrHelper.mapRectToScreen(target.box, payload.transform)
            OverlayLog.post("Tap @ (${mapped.centerX().toInt()}, ${mapped.centerY().toInt()}) for $result")
            tapCenter(mapped)
        }, {
            OverlayLog.post("OCR failure: ${it.message}")
            Toast.makeText(this, "فشل OCR", Toast.LENGTH_SHORT).show()
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
)
echo "$apply_svc" > app/src/main/java/com/math/app/AutoMathAccessibilityService.kt

echo "==> Building..."
./gradlew --no-daemon clean assembleDebug
echo "==> APKs:"
ls -lh app/build/outputs/apk/debug/
