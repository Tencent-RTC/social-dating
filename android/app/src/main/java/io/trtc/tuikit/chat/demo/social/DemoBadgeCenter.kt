package io.trtc.tuikit.chat.demo.social

import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.contact.ContactStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.ReceiveMessageOption

object DemoBadgeCenter {
    private val recent = MutableStateFlow(0)
    private val greeting = MutableStateFlow(0)
    private val friends = MutableStateFlow(0)
    private val _messagesSegment = MutableStateFlow(0)
    private val _total = MutableStateFlow(0)

    val messagesSegment: StateFlow<Int> = _messagesSegment.asStateFlow()
    val friendsSegment: StateFlow<Int> = friends.asStateFlow()
    val total: StateFlow<Int> = _total.asStateFlow()

    private var account: String? = null
    private var scope: CoroutineScope? = null

    fun ensureStarted(accountId: String) {
        if (scope != null && account == accountId) return
        stop()
        account = accountId
        val running = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        scope = running

        val contacts = ContactStore.shared
        contacts.loadFriendApplications(object : CompletionHandler {
            override fun onSuccess() {}
            override fun onFailure(code: Int, desc: String) {}
        })

        running.launch {
            DemoGroupWatcher.state.collect { view ->
                val candidates = view.badgeCandidates()
                recent.value = DemoBadgeRules.recentUnread(candidates)
                greeting.value = DemoBadgeRules.greetingUnread(candidates)
                publish()
            }
        }
        running.launch {
            contacts.state.friendApplicationUnreadCount.collect {
                friends.value = it.coerceAtLeast(0)
                publish()
            }
        }
    }

    fun stop() {
        scope?.cancel()
        scope = null
        account = null
        recent.value = 0
        greeting.value = 0
        friends.value = 0
        publish()
    }

    private fun publish() {
        _messagesSegment.value = DemoBadgeRules.messagesSegment(recent.value, greeting.value)
        _total.value = DemoBadgeRules.mainTab(_messagesSegment.value, friends.value)
    }
}

data class BadgeCandidate(
    val conversationId: String,
    val slot: ConversationSlot,
    val unreadCount: Int,
    val muted: Boolean = false
)

/**
 * The numbers on the Messages tab add up the unread messages the lists show (not the number of conversations):
 * recent unread + greeting unread on the 消息 segment, pending applications on the 好友 segment, the bottom tab is the sum.
 * A muted conversation shows only a dot in the list, so it adds nothing. Drafts and failed sends have no number either.
 */
object DemoBadgeRules {
    fun isValidRecent(c: BadgeCandidate): Boolean =
        c.conversationId.isNotEmpty() && c.slot == ConversationSlot.RECENT

    fun isValidGreeting(c: BadgeCandidate): Boolean =
        c.conversationId.isNotEmpty() && c.slot == ConversationSlot.GREETING

    private fun counted(c: BadgeCandidate): Int = if (c.muted) 0 else c.unreadCount.coerceAtLeast(0)

    fun recentUnread(list: List<BadgeCandidate>): Int =
        list.filter(::isValidRecent).distinctBy { it.conversationId }.sumOf(::counted)

    fun messagesSegment(recentUnread: Int, greetingUnread: Int): Int = recentUnread.coerceAtLeast(0) + greetingUnread.coerceAtLeast(0)

    fun mainTab(messagesSegment: Int, friendsSegment: Int): Int = messagesSegment.coerceAtLeast(0) + friendsSegment.coerceAtLeast(0)

    fun greetingUnread(list: List<BadgeCandidate>): Int =
        list.filter(::isValidGreeting).distinctBy { it.conversationId }.sumOf(::counted)
}

fun ConversationInfo.toBadgeCandidate(context: GreetingContext): BadgeCandidate = BadgeCandidate(
    conversationId = conversationID,
    slot = DemoConversationGroups.slot(toGreetingCandidate(), context),
    unreadCount = unreadCount,
    muted = receiveOption != ReceiveMessageOption.RECEIVE
)

fun GreetingView.badgeCandidates(): List<BadgeCandidate> = conversations.map { it.toBadgeCandidate(context) }
