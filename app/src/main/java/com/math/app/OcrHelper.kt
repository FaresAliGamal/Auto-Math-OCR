package com.math.app

import android.content.Context
import android.graphics.Rect
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object OcrHelper {

    suspend fun ocrOnScreen(ctx: Context): List<Pair<Rect, String>> = withContext(Dispatchers.Default) {
        val bmp = ScreenGrabber.capture() ?: return@withContext emptyList()
        val image = InputImage.fromBitmap(bmp, 0)
        val recog = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val result = Tasks.await(recog.process(image))
        val out = mutableListOf<Pair<Rect, String>>()
        for (block in result.textBlocks) {
            for (line in block.lines) {
                (line.boundingBox ?: Rect()).also { out.add(it to line.text) }
            }
        }
        out
    }

    fun pickBestMatch(ocr: List<Pair<Rect, String>>, target: String): Rect? {
        val normalized = target.replace("\s+".toRegex(), "").lowercase()
        return ocr.map { (rect, text) ->
            val cand = text.replace("\s+".toRegex(), "").lowercase()
            val score = when {
                cand == normalized -> 0
                cand.contains(normalized) || normalized.contains(cand) -> 1
                else -> levenshtein(cand, normalized)
            }
            Triple(score, rect, text)
        }.minByOrNull { it.first }?.second
    }

    private fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = i - 1
            dp[0] = i
            for (j in 1..b.length) {
                val temp = dp[j]
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                dp[j] = minOf(
                    dp[j] + 1,
                    dp[j - 1] + 1,
                    prev + cost
                )
                prev = temp
            }
        }
        return dp[b.length]
    }
}
