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

        // زر "تشغيل الآن" يرسل برودكاست للخدمة لبدء الحل فورًا
        val runIntent = Intent(AutoMathAccessibilityService.ACTION_TAP_TEXT)
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else 0
        val runPending = PendingIntent.getBroadcast(this, 0, runIntent, piFlags)

        val noti = NotificationCompat.Builder(this, CH_ID)
            .setSmallIcon(android.R.drawable.ic_media_play) // أي أيقونة نظام شغالة على كل الأجهزة
            .setContentTitle("التقاط الشاشة قيد التشغيل")
            .setContentText("اضغط تشغيل الآن لبدء حل السؤال الحالى")
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_play, "تشغيل الآن", runPending)
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
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
