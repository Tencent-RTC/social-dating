package io.trtc.tuikit.chat.uikit.components.messagelist.ui.popups
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.reactions.MessageReactionPanelPolicy
import kotlin.math.roundToInt

internal enum class LongPressPanelLevel {
    OPS,
    RECENT,
    ALL
}

internal object LongPressDimens {
    const val COLUMNS = 5
    const val MAX_ROWS = 2
    const val PAGE_SIZE = COLUMNS * MAX_ROWS

    const val SWITCH_ANIMATION_DURATION = 220L

    const val PAGE_INDICATOR_INACTIVE_ALPHA = 64

    fun screenMargin(density: Float): Int = 12.dp(density)

    fun visualGap(density: Float): Int = 4.dp(density)

    fun pageIndicatorDotSize(density: Float): Int = 5.dp(density)

    fun pageIndicatorDotSpacing(density: Float): Int = 4.dp(density)

    fun pageIndicatorVerticalPadding(density: Float): Int = 6.dp(density)

    fun pageIndicatorAreaHeight(density: Float): Int {
        return pageIndicatorDotSize(density) + pageIndicatorVerticalPadding(density) * 2
    }

    fun popupItemCellWidth(density: Float): Int = 52.dp(density)

    fun popupItemCellHeight(density: Float): Int = 58.dp(density)

    fun popupPageInset(density: Float): Int = 4.dp(density)

    fun popupPageVerticalPadding(density: Float): Int = popupPageInset(density) * 2

    fun popupDividerHeight(): Int = 0

    fun popupPageHeight(rowCount: Int, density: Float): Int {
        val safeRowCount = rowCount.coerceAtLeast(1)
        return popupPageVerticalPadding(density) +
            popupItemCellHeight(density) * safeRowCount +
            popupDividerHeight() * (safeRowCount - 1)
    }

    fun popupPagerVerticalPadding(): Int = 0

    fun resolveSinglePageColumnCount(itemCount: Int): Int {
        return COLUMNS
    }

    fun popupCardWidth(columnCount: Int, density: Float): Int {
        return popupItemCellWidth(density) * columnCount + popupPageInset(density) * 2
    }

    fun cardWidthForColumns(columnCount: Int, density: Float): Int {
        return popupCardWidth(columnCount, density)
    }

    fun emojiPanelHorizontalPadding(density: Float): Int = 8.dp(density)

    fun emojiPanelVerticalPadding(density: Float): Int = 6.dp(density)

    fun emojiPanelHeaderHeight(density: Float): Int = 36.dp(density)

    fun emojiPanelHeaderStartPadding(density: Float): Int = 6.dp(density)

    fun emojiPanelHeaderEndPadding(density: Float): Int = 14.dp(density)

    fun emojiPanelDividerMargin(density: Float): Int = 14.dp(density)

    fun emojiPanelDividerHeight(): Int = 1

    fun emojiPanelBackHeight(density: Float): Int = 28.dp(density)

    fun emojiPanelBackIconSize(density: Float): Int = 14.dp(density)

    fun emojiCellSize(density: Float): Int = 36.dp(density)

    fun emojiImageSize(density: Float): Int = 26.dp(density)

    fun emojiMoreCircleSize(density: Float): Int = 26.dp(density)

    fun emojiPanelRecentHeight(density: Float): Int {
        return emojiPanelVerticalPadding(density) * 2 +
            emojiCellSize(density) * MessageReactionPanelPolicy.RECENT_ROWS
    }

    fun emojiPanelAllHeight(density: Float): Int = 174.dp(density)

    fun emojiPanelBodyHeight(level: LongPressPanelLevel, density: Float): Int {
        return if (level == LongPressPanelLevel.ALL) {
            emojiPanelAllHeight(density)
        } else {
            emojiPanelRecentHeight(density)
        }
    }

    fun emojiPanelTotalHeight(level: LongPressPanelLevel, density: Float): Int {
        return emojiPanelHeaderHeight(density) +
            emojiPanelDividerHeight() +
            emojiPanelBodyHeight(level, density)
    }

    fun emojiPanelContentWidth(density: Float): Int {
        return emojiPanelHorizontalPadding(density) * 2 +
            emojiCellSize(density) * MessageReactionPanelPolicy.COLUMNS
    }

    private fun Int.dp(density: Float): Int = (this * density).roundToInt()
}
