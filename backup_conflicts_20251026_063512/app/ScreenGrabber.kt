package com.math.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager

object ScreenGrabber {
    private var mediaProjection: MediaProjection? = null
    private var mpCallback: MediaProjection.Callback? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var firstFrameWaited = false

    fun setProjection(mp: MediaProjection) {
        // فك أي كولباك قديم
        try { mpCallback?.let { mediaProjection?.unregisterCallback(it) } } catch (_: Exception) {}
        mediaProjection = mp
        firstFrameWaited = false

        // لازم نسجل كولباك قبل أي createVirtualDisplay()
        mpCallback = object : MediaProjection.Callback() {
            override fun onStop() {
                OverlayLog.post("MediaProjection onStop() -> release")
                release()
            }
        }
        mp.registerCallback(mpCallback!!, Handler(Looper.getMainLooper()))
        OverlayLog.post("Projection set ✅ (callback registered)")
    }

    fun hasProjection(): Boolean = mediaProjection != null

    fun release() {
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        try { imageReader?.close() } catch (_: Exception) {}
        imageReader = null
        try { mpCallback?.let { mediaProjection?.unregisterCallback(it) } } catch (_: Exception) {}
        mpCallback = null
        mediaProjection = null
        firstFrameWaited = false
        OverlayLog.post("Resources released")
    }

    fun capture(ctx: Context): Bitmap? {
        val mp = mediaProjection ?: run { OverlayLog.post("capture(): projection=null"); return null }
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        val width = dm.widthPixels
        val height = dm.heightPixels
        val dpi = dm.densityDpi

        if (imageReader == null) {
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            OverlayLog.post("ImageReader created ${width}x${height}")
        }
        if (virtualDisplay == null) {
            virtualDisplay = mp.createVirtualDisplay(
                "ocr-vd", width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC,
                imageReader!!.surface, null, null
            )
            OverlayLog.post("VirtualDisplay created")
        }

        if (!firstFrameWaited) {
            try { Thread.sleep(250) } catch (_: Exception) {}
            firstFrameWaited = true
        }

        val img = imageReader!!.acquireLatestImage() ?: run {
            Thread.sleep(120)
            imageReader!!.acquireLatestImage()
        } ?: run { OverlayLog.post("No image frame yet"); return null }

        val plane = img.planes[0]
        val buf = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width

        val bmp = Bitmap.createBitmap(
            width + rowPadding / pixelStride,
            height,
            Bitmap.Config.ARGB_8888
        )
        bmp.copyPixelsFromBuffer(buf)
        img.close()
        return Bitmap.createBitmap(bmp, 0, 0, width, height)
    }
}
