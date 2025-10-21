package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
import android.view.WindowManager

object ScreenGrabber {
private var mediaProjection: MediaProjection? = null
private var imageReader: ImageReader? = null
private var virtualDisplay: VirtualDisplay? = null

fun setProjection(mp: MediaProjection) {  
    mediaProjection = mp  
}  

fun capture(ctx: Context): Bitmap? {  
    val mp = mediaProjection ?: return null  
    val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager  
    val dm = DisplayMetrics()  
    @Suppress("DEPRECATION")  
    wm.defaultDisplay.getRealMetrics(dm)  
    val width = dm.widthPixels  
    val height = dm.heightPixels  
    val dpi = dm.densityDpi  

    if (imageReader == null) {  
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)  
    }  
    if (virtualDisplay == null) {  
        virtualDisplay = mp.createVirtualDisplay(  
            "ocr-vd", width, height, dpi,  
            DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,  
            imageReader!!.surface, null, null  
        )  
    }  

    val img = imageReader!!.acquireLatestImage() ?: run {  
        Thread.sleep(80)  
        imageReader!!.acquireLatestImage()  
    } ?: return null  

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
