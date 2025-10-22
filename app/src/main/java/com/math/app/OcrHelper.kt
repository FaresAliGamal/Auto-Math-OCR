package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.util.Log
import android.widget.Toast
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)

object OcrHelper {
private const val TAG = "OcrHelper"
private val recognizer by lazy {
TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
}

/** يحاول أولاً على cropped+preprocess ولو فشل يجرّب الشاشة كاملة */  
fun recognizeSmart(ctx: Context, fullBitmap: Bitmap,  
                   onDone: (Text) -> Unit, onError: (Exception) -> Unit) {  
    val roi = ImageUtils.cropBoard(fullBitmap)  
    val pre = ImageUtils.preprocessForDigits(roi)  

    recognizer.process(InputImage.fromBitmap(pre, 0))  
        .addOnSuccessListener { t1 ->  
            val ok1 = hasEquationOrChoices(t1)  
            Log.d(TAG, "Cropped OCR: ok=$ok1, blocks=${t1.textBlocks.size}")  
            if (ok1) {  
                onDone(t1)  
            } else {  
                // جرّب الشاشة كاملة (بدون قص)، مع نفس الـpreprocess الخفيف  
                val fullPre = ImageUtils.preprocessForDigits(fullBitmap)  
                recognizer.process(InputImage.fromBitmap(fullPre, 0))  
                    .addOnSuccessListener { t2 ->  
                        Log.d(TAG, "Full OCR fallback: blocks=${t2.textBlocks.size}")  
                        onDone(t2)  
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
            line.boundingBox?.let {  
                val txt = ImageUtils.normalizeDigitLike(line.text.trim())  
                Detected(txt, RectF(it))  
            }  
        }  
    }  

fun detectNumericChoices(t: Text): List<Detected> =  
    detectLines(t).map { d ->  
        d.copy(text = MathSolver.normalizeDigits(ImageUtils.normalizeDigitLike(d.text)))  
    }.filter { it.text.matches(Regex("^\\d+$")) }

}
