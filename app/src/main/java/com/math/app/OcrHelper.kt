package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)
data class OcrTransform(val originX: Float, val originY: Float, val scaleX: Float, val scaleY: Float)
data class OcrPayload(val text: Text, val transform: OcrTransform)

object OcrHelper {
    private const val TAG = "OcrHelper"
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /** يرجّع Text + Transform علشان نعرف نعمل mapping */
    fun recognizeSmart(ctx: Context, fullBitmap: Bitmap,
                       onDone: (OcrPayload) -> Unit, onError: (Exception) -> Unit) {
        // قص + بروسسنج
        val crop = ImageUtils.cropBoardWithRect(fullBitmap)
        recognizer.process(InputImage.fromBitmap(crop.bitmap, 0))
            .addOnSuccessListener { t1 ->
                val ok1 = hasEquationOrChoices(t1)
                Log.d(TAG, "Cropped OCR: ok=$ok1, blocks=${t1.textBlocks.size}")
                if (ok1) {
                    // الـOCR اشتغل على صورة مكبرة بمقياس crop.scale
                    val tr = OcrTransform(
                        originX = crop.rect.left.toFloat(),
                        originY = crop.rect.top.toFloat(),
                        scaleX  = 1f / crop.scale,
                        scaleY  = 1f / crop.scale
                    )
                    onDone(OcrPayload(t1, tr))
                } else {
                    // جرّب الشاشة كاملة (بنفس بروسسنج التكبير)
                    val fullPre = ImageUtils.preprocessForDigits(fullBitmap)
                    val s = fullPre.width.toFloat() / fullBitmap.width.toFloat()
                    recognizer.process(InputImage.fromBitmap(fullPre, 0))
                        .addOnSuccessListener { t2 ->
                            val tr = OcrTransform(0f, 0f, 1f / s, 1f / s)
                            Log.d(TAG, "Full OCR fallback: blocks=${t2.textBlocks.size}")
                            onDone(OcrPayload(t2, tr))
                        }
                        .addOnFailureListener(onError)
                }
            }
            .addOnFailureListener(onError)
    }

    private fun hasEquationOrChoices(t: Text): Boolean {
        val lines = detectLines(t)
        val eq = lines.firstOrNull { it.text.contains(Regex("[+\\-×x*/÷]")) }
        val nums = detectNumericChoices(t)
        return eq != null || nums.isNotEmpty()
    }

    fun detectLines(t: Text): List<Detected> =
        t.textBlocks.flatMap { b ->
            b.lines.mapNotNull { line ->
                line.boundingBox?.let { Detected(ImageUtils.normalizeDigitLike(line.text.trim()), RectF(it)) }
            }
        }

    fun detectNumericChoices(t: Text): List<Detected> =
        detectLines(t).map { d ->
            d.copy(text = MathSolver.normalizeDigits(ImageUtils.normalizeDigitLike(d.text)))
        }.filter { it.text.matches(Regex("^\\d+$")) }

    /** حوّل مستطيل من إحداثيات صورة الـOCR لإحداثيات الشاشة */
    fun mapRectToScreen(r: RectF, tr: OcrTransform): RectF =
        RectF(
            tr.originX + r.left * tr.scaleX,
            tr.originY + r.top * tr.scaleY,
            tr.originX + r.right * tr.scaleX,
            tr.originY + r.bottom * tr.scaleY
        )
}
