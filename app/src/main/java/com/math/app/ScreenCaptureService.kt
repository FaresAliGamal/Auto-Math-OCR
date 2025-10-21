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
