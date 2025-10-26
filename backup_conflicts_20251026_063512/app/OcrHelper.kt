package com.math.app

import android.content.Context
import android.graphics.*
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class Detected(val text: String, val box: RectF)
/** بنرجّع النص + مصفوفة تحويل من إحداثيات صورة الـOCR إلى إحداثيات الشاشة */
data class OcrPayload(val text: Text, val transform: Matrix)

object OcrHelper {
    private const val TAG = "OcrHelper"
    /** لازم يطابق التكبير اللي جوّا ImageUtils.preprocessForDigits */
    private const val SCALE = 2.5f

    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    /**
     * يحاول أولاً على قصّة اللوحة (مع تكبير)،
     * ولو النتيجة ضعيفة يجرب الشاشة كاملة (برضو مع تكبير).
     * onDone يستقبل OcrPayload يحتوي Matrix لتحويل الـRectF من إحداثيات OCR إلى الشاشة.
     */
    fun recognizeSmart(
        ctx: Context,
        fullBitmap: Bitmap,
        onDone: (OcrPayload) -> Unit,
        onError: (Exception) -> Unit
    ) {
        // 1) قصّ منتصف اللوحة
        val roi = ImageUtils.cropBoard(fullBitmap)
        // عملنا preprocess داخلياً من غير تعديل ImageUtils عشان نعرف الـ SCALE
        val roiPre = ImageUtils.preprocessForDigits(roi) // مُفترض SCALE=2.5

        // مصفوفة تحويل من إحداثيات roiPre -> شاشة كاملة:
        // أول حاجة نقسم على SCALE (نرجع لإحداثيات roi الأصلية)،
        // بعدين نعمل translate left/top الخاصة بـ crop
        val cropLeftTop = getCropLeftTop(fullBitmap, roi)
        val mCrop = Matrix().apply {
            // translate بعد الاسكيل (ترتيب الماتريكس في أندرويد postConcat)
            setScale(1f / SCALE, 1f / SCALE)
            postTranslate(cropLeftTop.first.toFloat(), cropLeftTop.second.toFloat())
        }

        recognizer.process(InputImage.fromBitmap(roiPre, 0))
            .addOnSuccessListener { t1 ->
                val ok1 = hasEquationOrChoices(t1)
                Log.d(TAG, "Cropped OCR: ok=$ok1, blocks=${t1.textBlocks.size}")
                if (ok1) {
                    onDone(OcrPayload(t1, mCrop))
                } else {
                    // 2) جرّب الشاشة كاملة مع نفس الرفع/التكبير
                    val fullPre = ImageUtils.preprocessForDigits(fullBitmap)
                    val mFull = Matrix().apply {
                        setScale(1f / SCALE, 1f / SCALE) // من fullPre إلى fullBitmap
                    }
                    recognizer.process(InputImage.fromBitmap(fullPre, 0))
                        .addOnSuccessListener { t2 ->
                            Log.d(TAG, "Full OCR fallback: blocks=${t2.textBlocks.size}")
                            onDone(OcrPayload(t2, mFull))
                        }
                        .addOnFailureListener(onError)
                }
            }
            .addOnFailureListener(onError)
    }

    /** نحاول نعرف إزاحة القصّ اللي عملها ImageUtils.cropBoard */
    private fun getCropLeftTop(full: Bitmap, roi: Bitmap): Pair<Int, Int> {
        // cropBoard بيحسب left/top كالتالي (شوف ImageUtils):
        val w = full.width; val h = full.height
        val cw = (w * 0.70f).toInt()
        val ch = (h * 0.55f).toInt()
        val left = ((w - cw) / 2f).toInt().coerceAtLeast(0)
        val top  = ((h * 0.22f)).toInt().coerceAtLeast(0)
        return left to top
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

    /** طبّق المصفوفة على صندوق وأرجع إحداثيات الشاشة */
    fun mapRectToScreen(src: RectF, transform: Matrix): RectF {
        val out = RectF(src)
        transform.mapRect(out)
        return out
    }
}
