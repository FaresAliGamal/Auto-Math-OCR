package com.math.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.widget.Toast
import com.math.app.databinding.ActivityMainBinding

class MainActivity : Activity() {
    private lateinit var b: ActivityMainBinding
    private val REQ_CAPTURE = 333

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)

        b.btnCapture.setOnClickListener {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE)
        }

        b.btnTest.setOnClickListener {
            Toast.makeText(this, "Ready. Trigger from service.", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CAPTURE && resultCode == RESULT_OK && data != null) {
            AutoMathAccessibilityService.handoverProjection(resultCode, data)
            Toast.makeText(this, "Screen capture permission granted", Toast.LENGTH_SHORT).show()
        }
    }
}
