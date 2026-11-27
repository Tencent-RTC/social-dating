package com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.LruCache

object PeerAvatarMemory {
    private const val MAX_EDGE = 320
    private const val MAX_ENTRIES = 8

    private val bitmaps = LruCache<String, Bitmap>(MAX_ENTRIES)

    fun drawable(context: Context, url: String): Drawable? {
        val bitmap = synchronized(bitmaps) { bitmaps.get(url) } ?: return null
        return BitmapDrawable(context.resources, bitmap)
    }

    fun remember(context: Context, url: String, filePath: String): Drawable? {
        if (url.isEmpty()) return null
        drawable(context, url)?.let { return it }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(filePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MAX_EDGE && bounds.outHeight / (sample * 2) >= MAX_EDGE) sample *= 2
        val bitmap = BitmapFactory.decodeFile(filePath, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        synchronized(bitmaps) { bitmaps.put(url, bitmap) }
        return BitmapDrawable(context.resources, bitmap)
    }
}
