package com.fares.automathocr

import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var blackBoxText: TextView
    private lateinit var previewImage: ImageView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        blackBoxText = findViewById(R.id.blackBoxText)
        previewImage = findViewById(R.id.previewImage)
        val btnUpload = findViewById<Button>(R.id.btnUpload)

        val pickImageLauncher = registerForActivityResult(
            ActivityResultContracts.GetContent()
        ) { uri: Uri? ->
            if (uri != null) {
                previewImage.setImageURI(uri)
                blackBoxText.text = "تم اختيار الصورة بنجاح ✅"
            } else {
                Toast.makeText(this, "لم يتم اختيار أي صورة", Toast.LENGTH_SHORT).show()
            }
        }

        btnUpload.setOnClickListener {
            pickImageLauncher.launch("image/*")
        }
    }
}
