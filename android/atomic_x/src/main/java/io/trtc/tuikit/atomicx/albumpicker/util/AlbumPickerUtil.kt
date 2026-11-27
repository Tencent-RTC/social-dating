/*
 * Copyright (c) 2025 Tencent
 * All rights reserved.
 *
 * Author: eddardliu
 */

package io.trtc.tuikit.atomicx.albumpicker.util

import android.content.Context
import android.util.TypedValue

object AlbumPickerUtil {
    fun dpToPx(context: Context, dp: Int): Int =
        TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                dp.toFloat(),
                context.resources.displayMetrics,
            ).toInt()
}
