package io.trtc.tuikit.chat.uikit.components.conversationlist.ui

import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.conversationlist.model.ConversationActionIDs
import io.trtc.tuikit.chat.uikit.components.conversationlist.model.ConversationCustomAction

/**
 * Spec of the conversation long-press menu (S2) and the left-swipe actions, taken from the
 * design "527:636" / prototype `.ctxmenu` and `.conv-swipe`.
 */
internal object ConversationMenuSpec {
    const val MENU_WIDTH_DP = 168
    const val MENU_ITEM_HEIGHT_DP = 44
    const val MENU_RADIUS_DP = 8
    const val MENU_ICON_DP = 20
    const val MENU_ICON_GAP_DP = 10
    const val MENU_PADDING_H_DP = 14
    const val MENU_TEXT_SP = 14f
    const val DIVIDER_DP = 1

    const val SWIPE_ACTION_WIDTH_DP = 72
    const val SWIPE_TEXT_SP = 13f
    const val SWIPE_ICON_DP = 18

    /** Long-press menu order of the prototype: pin, mute, unread, clear, delete. */
    private val menuOrder = listOf(
        ConversationActionIDs.PIN,
        ConversationActionIDs.MUTE,
        ConversationActionIDs.MARK_UNREAD,
        ConversationActionIDs.CLEAR_HISTORY,
        ConversationActionIDs.DELETE,
    )

    /** Left-swipe only offers three actions, same semantics as the long-press menu. */
    val swipeActionIDs: List<String> = listOf(
        ConversationActionIDs.PIN,
        ConversationActionIDs.MUTE,
        ConversationActionIDs.DELETE,
    )

    fun menuHeightDp(itemCount: Int): Int {
        if (itemCount <= 0) return 0
        return itemCount * MENU_ITEM_HEIGHT_DP + (itemCount - 1) * DIVIDER_DP
    }

    fun swipeRevealWidthDp(actionCount: Int): Int = actionCount * SWIPE_ACTION_WIDTH_DP

    /** Known actions first (prototype order), custom actions keep their relative order after them. */
    fun orderForMenu(actions: List<ConversationCustomAction>): List<ConversationCustomAction> {
        val known = menuOrder.mapNotNull { id -> actions.firstOrNull { it.ID == id } }
        val custom = actions.filter { it.ID !in menuOrder }
        return known + custom
    }

    fun swipeActionsOf(actions: List<ConversationCustomAction>): List<ConversationCustomAction> {
        return swipeActionIDs.mapNotNull { id -> actions.firstOrNull { it.ID == id } }
    }

    fun menuIconRes(actionID: String): Int = when (actionID) {
        ConversationActionIDs.PIN -> R.drawable.conversation_list_menu_pin_icon
        ConversationActionIDs.MUTE -> R.drawable.conversation_list_menu_mute_icon
        ConversationActionIDs.MARK_UNREAD -> R.drawable.conversation_list_menu_unread_icon
        ConversationActionIDs.CLEAR_HISTORY -> R.drawable.conversation_list_menu_clear_icon
        ConversationActionIDs.DELETE -> R.drawable.conversation_list_menu_delete_icon
        else -> 0
    }
}
