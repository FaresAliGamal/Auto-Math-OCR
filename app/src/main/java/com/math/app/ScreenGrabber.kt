package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager

object ScreenGrabber {
private const val TAG = "ScreenGrabber"
private var mediaProjection: MediaProjection? = null
private var imageReader: ImageReader? = null
private var virtualDisplay: VirtualDisplay? = null
private var firstFrameWaited = false

fun setProjection(mp: MediaProjection) {  
    mediaProjection = mp  
    firstFrameWaited = false  
}  

fun hasProjection(): Boolean = mediaProjection != null  

fun capture(ctx: Context): Bitmap? {  
    val mp = mediaProjection ?: run {  
        Log.w(TAG, "capture(): mediaProjection == null")  
        return null  
    }  
    val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager  
    val dm = DisplayMetrics()  
    @Suppress("DEPRECATION")  
    wm.defaultDisplay.getRealMetrics(dm)  
    val width = dm.widthPixels  
    val height = dm.heightPixels  
    val dpi = dm.densityDpi  

    if (imageReader == null) {  
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)  
        Log.d(TAG, "ImageReader created ${width}x${height}")  
    }  
    if (virtualDisplay == null) {  
        virtualDisplay = mp.createVirtualDisplay(  
            "ocr-vd", width, height, dpi,  
            DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,  
            imageReader!!.surface, null, null  
        )  
        Log.d(TAG, "VirtualDisplay created")  
    }  

    // مهلة أول فريم  
    if (!firstFrameWaited) {  
        try { Thread.sleep(250) } catch (_: InterruptedException) {}  
        firstFrameWaited = true  
    }  

    val img = imageReader!!.acquireLatestImage() ?: run {  
        Thread.sleep(120)  
        imageReader!!.acquireLatestImage()  
    } ?: run {  
        Log.w(TAG, "No image frame yet")  
        return null  
    }  

    val plane = img.planes[0]  
    val buf = plane.buffer  
    val pixelStride = plane.pixelStride  
    val rowStride = plane.rowStride  
    val rowPadding = rowStride - pixelStride * width  
    val bmp = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888)  
    bmp.copyPixelsFromBuffer(buf)  
    img.close()  
    return Bitmap.createBitmap(bmp, 0, 0, width, height)  
}

}
