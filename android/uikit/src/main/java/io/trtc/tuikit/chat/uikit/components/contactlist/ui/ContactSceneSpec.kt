package io.trtc.tuikit.chat.uikit.components.contactlist.ui

/**
 * Spec of the contacts list (S5), the new-contacts page (S5b) taken from the prototype
 * `.centry / .contact / .idxheader / .alphaindex / .reqrow` (uikit.css).
 */
object ContactSceneSpec {
    const val ENTRY_HEIGHT_DP = 60
    const val ENTRY_ICON_DP = 40
    const val ENTRY_ICON_RADIUS_DP = 12
    const val ENTRY_ICON_GLYPH_DP = 24
    const val ENTRY_TITLE_SP = 18
    const val ENTRY_GAP_DP = 12
    const val PAGE_PADDING_DP = 16

    /** 16 padding + 40 avatar + 12 gap: dividers start where the text starts. */
    const val DIVIDER_INSET_DP = 68
    const val SECTION_HEADER_HEIGHT_DP = 32

    /** Rows leave room for the index bar on the trailing side. */
    const val ROW_END_INSET_DP = 40

    const val INDEX_ITEM_WIDTH_DP = 20
    const val INDEX_ITEM_HEIGHT_DP = 18
    const val INDEX_FONT_SP = 10
    const val INDEX_SELECTED_DP = 18

    const val BADGE_MIN_DP = 18
    const val BADGE_TEXT_SP = 11

    const val REQUEST_ROW_HEIGHT_DP = 72
    const val REQUEST_AVATAR_DP = 48
    const val REQUEST_NAME_SP = 16
    const val REQUEST_MESSAGE_SP = 13
    const val REQUEST_BUTTON_HEIGHT_DP = 28
    const val REQUEST_BUTTON_RADIUS_DP = 14
    const val REQUEST_BUTTON_PADDING_DP = 14
    const val REQUEST_BUTTON_SP = 12
    const val REQUEST_ADDED_SP = 13

    const val SEARCH_ENTRY_HEIGHT_DP = 36
    const val SEARCH_ENTRY_RADIUS_DP = 10
    const val SEARCH_ENTRY_TEXT_SP = 14
    const val SEARCH_ENTRY_PADDING_TOP_DP = 4
    const val SEARCH_ENTRY_PADDING_BOTTOM_DP = 12

    fun badgeText(count: Int): String = when {
        count <= 0 -> ""
        count > 99 -> "99+"
        else -> count.toString()
    }
}
