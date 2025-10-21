set -euo pipefail

cat > app/src/main/java/com/math/app/MainActivity.kt <<'KOT'
package com.math.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
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

    private val notifPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* no-op */ }

    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            val svcIntent = Intent(this, ScreenCaptureService::class.java).apply {
                putExtra(ScreenCaptureService.EXTRA_CODE, result.resultCode)
                putExtra(ScreenCaptureService.EXTRA_DATA, result.data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(this, svcIntent)
            } else {
                startService(svcIntent)
            }
            renderStatus()
        } else {
            status.text = "❌ تم رفض إذن التقاط الشاشة"
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
            // تحقّق من الشروط أولًا
            val accOn = AutoMathAccessibilityService.isEnabled(this)
            val projOn = ScreenGrabber.hasProjection()

            if (!accOn) {
                status.text = "⚠️ فعّل خدمة الوصول للتطبيق أولًا"
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                return@setOnClickListener
            }
            if (!projOn) {
                status.text = "⚠️ التقاط الشاشة غير مفعّل — اضغط ”ابدأ“ واسمح بالتسجيل"
                return@setOnClickListener
            }

            val i = Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT)
            i.putExtra("target", targetInput.text.toString())
            sendBroadcast(i)
            status.text = "جارٍ التشغيل…"
        }

        requestNotifPermissionIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        renderStatus()
    }

    private fun renderStatus() {
        val accOn = AutoMathAccessibilityService.isEnabled(this)
        val projOn = ScreenGrabber.hasProjection()

        val acc = if (accOn) "خدمة الوصول: ✅" else "خدمة الوصول: ⛔"
        val proj = if (projOn) "التقاط الشاشة: ✅" else "التقاط الشاشة: ⛔"
        status.text = "$acc    |    $proj"
    }

    private fun requestNotifPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val nm = NotificationManagerCompat.from(this)
            if (!nm.areNotificationsEnabled()) {
                notifPermLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }
}
KOT

./gradlew --no-daemon assembleDebug
