package com.math.app

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

object OcrRegionsHelper {
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    fun recognizeBitmap(bmp: Bitmap, onOk:(Text)->Unit, onErr:(Exception)->Unit){
        recognizer.process(InputImage.fromBitmap(bmp,0))
            .addOnSuccessListener(onOk)
            .addOnFailureListener(onErr)
    }

    fun bestLineDigits(t: Text): String {
        val lines = t.textBlocks.flatMap { it.lines }
        val norm = lines.map { ImageUtils.normalizeDigitLike(it.text) }.filter { it.isNotBlank() }
        return norm.maxByOrNull { it.length } ?: ""
    }

    fun allLines(t: Text): List<String> =
        t.textBlocks.flatMap { it.lines }.map { ImageUtils.normalizeDigitLike(it.text) }
}
