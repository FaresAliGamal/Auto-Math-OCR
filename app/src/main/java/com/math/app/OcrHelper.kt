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
        // قص اللوحة + معالجة/تكبير قبل الـOCR
        val roi = ImageUtils.cropBoard(bitmap)
        val pre = ImageUtils.preprocessForDigits(roi)
        recognizer.process(InputImage.fromBitmap(pre, 0))
            .addOnSuccessListener(onDone)
            .addOnFailureListener(onError)
    }

    fun detectLines(t: Text): List<Detected> =
        t.textBlocks.flatMap { b ->
            b.lines.mapNotNull { line ->
                line.boundingBox?.let {
                    // طبّع الغلطات الشائعة
                    val txt = ImageUtils.normalizeDigitLike(line.text.trim())
                    Detected(txt, RectF(it))
                }
            }
        }

    fun detectNumericChoices(t: Text): List<Detected> =
        detectLines(t).map { d ->
            d.copy(text = MathSolver.normalizeDigits(ImageUtils.normalizeDigitLike(d.text)))
        }.filter { it.text.matches(Regex("^[\\d]+$")) }
}
