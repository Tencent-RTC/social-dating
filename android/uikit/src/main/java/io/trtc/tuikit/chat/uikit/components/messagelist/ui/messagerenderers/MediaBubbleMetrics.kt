package io.trtc.tuikit.chat.uikit.components.messagelist.ui.messagerenderers

/**
 * Image and video bubble geometry per design S4 / board F (prototype `.bubble--image`, `.bubble--video`,
 * `.playbadge--video`, `.bubble__dur`). Landscape frames are the design sizes; portrait media uses the
 * transposed frame (product choice: the design only shipped landscape). The thumbnail is center-cropped
 * into that frame and the full media opens in the viewer.
 *
 * 2026-11-11: the whole media bubble (frame, corners, play badge, duration pill) is the design size scaled
 * by 15% — both platforms together — because the design frames read small next to the gift/quick-row cards.
 * Inner geometry is scaled with the frame so the bubble keeps the design's proportions; the duration label
 * stays at 10sp so typography does not drift.
 */
internal object MediaBubbleMetrics {
    const val IMAGE_WIDTH_DP = 173
    const val IMAGE_HEIGHT_DP = 138
    const val IMAGE_PORTRAIT_MAX_HEIGHT_DP = 230
    const val IMAGE_RADIUS_DP = 14

    const val VIDEO_WIDTH_DP = 202
    const val VIDEO_HEIGHT_DP = 136
    const val VIDEO_RADIUS_DP = 16

    const val PLAY_BADGE_DP = 46
    const val PLAY_GLYPH_DP = 18
    const val PLAY_BADGE_RING_DP = 1
    const val PLAY_BADGE_FILL = 0x33FFFFFF
    const val PLAY_BADGE_RING = 0x8CFFFFFF.toInt()

    const val DURATION_LEFT_DP = 133
    const val DURATION_TOP_DP = 107
    const val DURATION_HEIGHT_DP = 20
    const val DURATION_PADDING_DP = 8
    const val DURATION_RADIUS_DP = 10
    const val DURATION_TEXT_SP = 10f
    const val DURATION_FILL = 0x8C000000.toInt()

    data class Size(val widthDp: Int, val heightDp: Int)

    fun isPortrait(width: Int, height: Int): Boolean = width > 0 && height > width

    fun imageFrame(width: Int, height: Int): Size =
        if (isPortrait(width, height)) {
            val scaled = Math.round(IMAGE_WIDTH_DP * height.toFloat() / width)
            Size(IMAGE_WIDTH_DP, scaled.coerceIn(IMAGE_WIDTH_DP, IMAGE_PORTRAIT_MAX_HEIGHT_DP))
        } else {
            Size(IMAGE_WIDTH_DP, IMAGE_HEIGHT_DP)
        }

    fun videoFrame(width: Int, height: Int): Size =
        if (isPortrait(width, height)) Size(VIDEO_HEIGHT_DP, VIDEO_WIDTH_DP)
        else Size(VIDEO_WIDTH_DP, VIDEO_HEIGHT_DP)

    fun durationLeftDp(portrait: Boolean): Int =
        if (portrait) VIDEO_HEIGHT_DP - (VIDEO_WIDTH_DP - DURATION_LEFT_DP) else DURATION_LEFT_DP

    fun durationTopDp(portrait: Boolean): Int =
        if (portrait) VIDEO_WIDTH_DP - (VIDEO_HEIGHT_DP - DURATION_TOP_DP) else DURATION_TOP_DP
}
