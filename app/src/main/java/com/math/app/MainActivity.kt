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

    // طلب إذن الإشعارات (Android 13+)
    private val notifPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            status.text = "⚠️ تم رفض إذن الإشعارات. يمكنك تفعيله من الإعدادات."
            // افتح إعدادات إشعارات التطبيق مباشرة لو حابب
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            startActivity(intent)
        }
    }

    // نتيجة التقاط الشاشة
    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            // تأكد من إذن الإشعارات قبل تشغيل الخدمة (لزر "تشغيل الآن")
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
    }

    private fun requestNotifPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val nm = NotificationManagerCompat.from(this)
            val enabled = nm.areNotificationsEnabled()
            if (!enabled) {
                notifPermLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }
}
