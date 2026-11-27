package io.trtc.tuikit.chat.uikit.components.conversationlist.config

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * A store made by `ConversationListStore.create(group)` loads a correctly filtered first page, but
 * afterwards merges every live conversation event into its list without checking the group it is
 * bound to. A group-bound list therefore re-checks membership itself, and reloads when membership
 * changes underneath it (the SDK does not push a conversation change for add/remove-from-group).
 */
object ConversationGroupMembership {
    private val builtInGroups = setOf("_c2c_", "_group_", "_hasUnreadCount_", "_hasGroupAtInfo_")

    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 8)
    val changes: SharedFlow<Unit> = _changes.asSharedFlow()

    fun notifyChanged() {
        _changes.tryEmit(Unit)
    }

    /** Built-in filters (C2C / group chats / unread / @me) are not custom groups and carry no membership. */
    fun isCustomGroup(group: String?): Boolean = !group.isNullOrEmpty() && group !in builtInGroups

    fun isMember(group: String?, memberships: List<String>?): Boolean =
        !isCustomGroup(group) || memberships?.contains(group) == true

    fun exclusion(group: String?, base: ConversationMatcher?): ConversationMatcher? {
        if (!isCustomGroup(group)) return base
        return ConversationMatcher { conversation ->
            !isMember(group, conversation.conversationGroupList) || base?.matches(conversation) == true
        }
    }
}
