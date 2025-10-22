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
