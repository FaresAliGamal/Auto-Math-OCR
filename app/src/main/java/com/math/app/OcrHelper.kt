package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)

object OcrHelper {
    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    fun recognize(ctx: Context, bitmap: Bitmap,
                  onDone: (Text) -> Unit, onError: (Exception) -> Unit) {
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener(onDone)
            .addOnFailureListener(onError)
    }

    fun detectLines(t: Text): List<Detected> =
        t.textBlocks.flatMap { b ->
            b.lines.mapNotNull { line ->
                line.boundingBox?.let { Detected(line.text.trim(), RectF(it)) }
            }
        }

    fun detectNumericChoices(t: Text): List<Detected> =
        detectLines(t).filter { it.text.matches(Regex("^[\\d٠-٩]+$")) }
}
