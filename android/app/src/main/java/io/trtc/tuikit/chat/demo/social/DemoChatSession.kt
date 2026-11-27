package io.trtc.tuikit.chat.demo.social

import io.trtc.tuikit.chat.uikit.components.messageinput.data.MessageInputPanel

/** Chat chrome that lives for one app session: dismissed safety tips and the seen-gift dot. */
object DemoChatSession {
    private val dismissedBanners = HashSet<String>()
    private var giftDotSeen = false

    @Synchronized
    fun isBannerDismissed(conversationId: String): Boolean = conversationId in dismissedBanners

    @Synchronized
    fun dismissBanner(conversationId: String) {
        dismissedBanners += conversationId
    }

    @Synchronized
    fun isGiftDotSeen(): Boolean = giftDotSeen

    @Synchronized
    fun markGiftDotSeen() {
        giftDotSeen = true
    }

    @Synchronized
    fun reset() {
        dismissedBanners.clear()
        giftDotSeen = false
    }
}

/**
 * Which real test account a fixture person was bound to during this session. Fixture ids are
 * never message targets; the binding only decides which real userID the "say hi" shortcut opens.
 */
object DemoSessionBindings {
    private val bound = HashMap<String, String>()

    @Synchronized
    fun peerOf(fixtureId: String): String? = bound[fixtureId]

    @Synchronized
    fun fixtureOf(userId: String): String? = bound.entries.firstOrNull { it.value == userId }?.key

    @Synchronized
    fun bind(fixtureId: String, userId: String) {
        bound[fixtureId] = userId
    }

    @Synchronized
    fun reset() = bound.clear()
}

object DemoQuickRowPolicy {
    fun isOn(actionId: String, panel: MessageInputPanel): Boolean = when (actionId) {
        "more" -> panel == MessageInputPanel.MORE
        "emoji" -> panel == MessageInputPanel.EMOJI
        else -> false
    }

    fun collapsesPanelFirst(actionId: String, panel: MessageInputPanel): Boolean {
        val panelOpen = panel == MessageInputPanel.MORE || panel == MessageInputPanel.EMOJI
        return panelOpen && actionId != "more" && actionId != "emoji"
    }

    fun iconState(actionId: String, panel: MessageInputPanel): String =
        if (actionId == "more" && panel == MessageInputPanel.MORE) "on" else "off"
}
