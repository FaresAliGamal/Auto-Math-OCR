package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.graphics.Point
import android.hardware.display.DisplayManager
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.view.WindowManager

object ScreenGrabber {
    private var projection: MediaProjection? = null
    private var reader: ImageReader? = null
    private var width = 0
    private var height = 0

    fun init(ctx: Context, resultCode: Int, data: android.content.Intent) {
        val mpm = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = mpm.getMediaProjection(resultCode, data)

        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val size = Point().also { wm.defaultDisplay.getRealSize(it) }
        width = size.x; height = size.y
        val dpi = ctx.resources.displayMetrics.densityDpi

        reader?.close()
        reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        projection!!.createVirtualDisplay(
            "cap", width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader!!.surface, null, null
        )
    }

    fun capture(): Bitmap? {
        val img = reader?.acquireLatestImage() ?: return null
        val plane = img.planes[0]
        val buf = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * img.width
        val bmp = Bitmap.createBitmap(
            img.width + rowPadding / pixelStride, img.height, Bitmap.Config.ARGB_8888
        )
        bmp.copyPixelsFromBuffer(buf)
        img.close()
        return Bitmap.createBitmap(bmp, 0, 0, width, height)
    }

    fun release() { reader?.close(); projection?.stop(); reader = null; projection = null }
}
