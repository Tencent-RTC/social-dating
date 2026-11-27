package io.trtc.tuikit.chat.uikit.components.messagelist.ui.reactions

import io.trtc.tuikit.atomicxcore.api.message.MessageReaction

object MessageReactionPanelPolicy {
    const val COLUMNS = 7
    const val RECENT_ROWS = 2
    const val RECENT_COUNT = COLUMNS * RECENT_ROWS - 1

    fun displayable(reactions: List<MessageReaction>): List<MessageReaction> {
        return reactions.filter { it.reactionID.isNotBlank() && it.totalUserCount > 0 }
    }
}
