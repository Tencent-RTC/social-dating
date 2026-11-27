package io.trtc.tuikit.chat.demo.social

import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationMarkType
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationType
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import io.trtc.tuikit.atomicxcore.api.message.MessageStatus
import io.trtc.tuikit.atomicxcore.api.message.MessageType
import io.trtc.tuikit.chat.uikit.components.messagelist.typing.TypingMessageProtocol
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallMessageParser

enum class LastMessageKind { NONE, MINE_SENT, MINE_UNSENT, OTHER }

enum class ConversationSlot { GREETING, RECENT, PENDING, HIDDEN }

data class GreetingCandidate(
    val conversationId: String,
    val isC2C: Boolean,
    val peerId: String,
    val marked: Boolean,
    val last: LastMessageKind,
    val stamp: Long = 0L
)

data class GreetingContext(
    val decided: Set<String> = emptySet(),
    val friends: Set<String>? = null,
    val friendsFailed: Boolean = false,
    val failed: Set<String> = emptySet(),
    val marking: Set<String> = emptySet(),
    val disabled: Boolean = false
)

data class GreetingPlan(
    val decide: List<String> = emptyList(),
    val unmark: List<String> = emptyList(),
    val inspect: List<String> = emptyList()
) {
    val isEmpty: Boolean get() = decide.isEmpty() && unmark.isEmpty() && inspect.isEmpty()
}

object DemoConversationGroups {
    fun slot(c: GreetingCandidate, ctx: GreetingContext): ConversationSlot {
        if (!c.isC2C || c.conversationId.isEmpty()) return ConversationSlot.HIDDEN
        if (ctx.disabled || isRecent(c, ctx)) return ConversationSlot.RECENT
        if (c.marked || c.conversationId in ctx.marking) return ConversationSlot.GREETING
        if (c.last == LastMessageKind.NONE || c.last == LastMessageKind.MINE_UNSENT) return ConversationSlot.RECENT
        if (c.conversationId in ctx.failed) return ConversationSlot.RECENT
        if (ctx.friends == null && ctx.friendsFailed) return ConversationSlot.RECENT
        return ConversationSlot.PENDING
    }

    fun plan(
        candidates: Collection<GreetingCandidate>,
        ctx: GreetingContext,
        busy: Set<String> = emptySet()
    ): GreetingPlan {
        if (ctx.disabled) return GreetingPlan()
        val decide = mutableListOf<String>()
        val unmark = mutableListOf<String>()
        val inspect = mutableListOf<String>()
        val seen = HashSet<String>()
        for (c in candidates) {
            val id = c.conversationId
            if (!c.isC2C || id.isEmpty() || !seen.add(id) || id in busy) continue
            val decided = id in ctx.decided
            val evidence = isFriend(c, ctx) || c.last == LastMessageKind.MINE_SENT
            when {
                c.marked -> if (decided || evidence) {
                    if (!decided) decide += id
                    unmark += id
                }
                decided -> Unit
                evidence || c.last == LastMessageKind.MINE_UNSENT -> decide += id
                c.last == LastMessageKind.NONE -> Unit
                id in ctx.marking || id in ctx.failed || ctx.friends == null -> Unit
                else -> inspect += id
            }
        }
        return GreetingPlan(decide, unmark, inspect)
    }

    fun hasReply(history: List<LastMessageKind>): Boolean =
        history.any { it == LastMessageKind.MINE_SENT || it == LastMessageKind.MINE_UNSENT }

    private fun isRecent(c: GreetingCandidate, ctx: GreetingContext): Boolean =
        c.conversationId in ctx.decided || isFriend(c, ctx) || c.last == LastMessageKind.MINE_SENT

    private fun isFriend(c: GreetingCandidate, ctx: GreetingContext): Boolean =
        ctx.friends?.contains(c.peerId) == true
}

object DemoConversationClassifier {
    val GREETING_MARK: ConversationMarkType = ConversationMarkType.fold
    private const val C2C_PREFIX = "c2c_"

    fun kindOf(message: MessageInfo?): LastMessageKind {
        val m = message ?: return LastMessageKind.NONE
        if (m.messageType == MessageType.TIPS ||
            TypingMessageProtocol.isTypingMessage(m) ||
            CallMessageParser.isCallMessage(m)
        ) return LastMessageKind.OTHER
        if (!m.isSentBySelf) return LastMessageKind.OTHER
        return if (m.status == MessageStatus.SEND_SUCCESS) LastMessageKind.MINE_SENT else LastMessageKind.MINE_UNSENT
    }

    fun isGreetingMarked(info: ConversationInfo): Boolean =
        info.conversationMarkList.any { it.contains(GREETING_MARK) }

    fun candidate(info: ConversationInfo): GreetingCandidate = GreetingCandidate(
        conversationId = info.conversationID,
        isC2C = info.type == ConversationType.C2C,
        peerId = info.conversationID.removePrefix(C2C_PREFIX),
        marked = isGreetingMarked(info),
        last = kindOf(info.lastMessage),
        stamp = info.lastMessage?.timestamp ?: 0L
    )
}

fun ConversationInfo.toGreetingCandidate(): GreetingCandidate = DemoConversationClassifier.candidate(this)
