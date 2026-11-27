package io.trtc.tuikit.chat.uikit.components.chatsetting.model

/**
 * Host supplied extras for the 1:1 chat settings scene (S6). Everything here is business content
 * that the IM SDK does not own, so every row is a host decision: the UIKit only renders it.
 * Rows built from these extras are local only; they never submit a business request.
 *
 * Passing extras switches the page to the scene look (profile box, rounded setting cards, footer)
 * and the order mute, pin / intimacy, bubble background, nickname / blacklist, report, clear.
 */
data class C2CSceneExtras(
    /** Capsule tags under the user id, e.g. 已认证 / 民谣. */
    val profileTags: List<String> = emptyList(),
    /** Host-built badge shown under the user id (replaces [profileTags] when set), e.g. the 实名 tag. */
    val profileTagView: ((android.content.Context) -> android.view.View)? = null,
    val intimacyLabel: String,
    val intimacyBadge: String? = null,
    val backgroundLabel: String,
    val nicknameLabel: String,
    val nicknameValue: String? = null,
    val reportLabel: String,
    val footer: String? = null,
    /** When set, a host row「加好友」is rendered above the blacklist row; the host hides it for friends. */
    val addFriendLabel: String? = null,
    val onAddFriendClick: () -> Unit = {},
    /** When set, a danger row「删除好友」is rendered at the bottom (after 清空聊天记录); friends only. */
    val deleteFriendLabel: String? = null,
    /** Called with [ROW_INTIMACY], [ROW_NICKNAME] or [ROW_REPORT] when a local row is tapped. */
    val onMockRowClick: (String) -> Unit = {},
) {
    companion object {
        const val ROW_INTIMACY = "intimacy"
        const val ROW_NICKNAME = "nickname"
        const val ROW_REPORT = "report"
    }
}
