package io.trtc.tuikit.chat.uikit.components.conversationlist.utils

import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationListStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationMarkType
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

private const val UNMARK_BATCH_SIZE = 100

/**
 * 清未读的统一入口。
 *
 * 一个会话的“未读”有两部分：未读数（unreadCount）和“标记未读”（ConversationMarkType.unread）。
 * 只调 clearConversationUnreadCount 清不掉标记，列表里仍会显示红点/未读；
 * 只取 unreadCount > 0 做筛选，则会漏掉“只有标记、没有未读数”的会话。
 *
 * 这里统一成：先去掉“标记未读”，等它完成后再清未读数。顺序不能反：数字先清成 0 而标记还在的话，
 * 角标会先变成一个红点，等标记去掉后才消失。
 */
object ConversationUnreadClearer {

    /** 清掉这些会话的未读数和“标记未读”。标记只对带标记的会话去掉，没有标记的不发请求。 */
    fun clearConversationsUnread(
        store: ConversationListStore,
        conversations: List<ConversationInfo>,
        completion: CompletionHandler? = null
    ) {
        clearUnread(
            store = store,
            conversationIDs = conversations.map { it.conversationID },
            markedConversationIDs = conversations
                .filter { it.conversationMarkList.contains(ConversationMarkType.unread) }
                .map { it.conversationID },
            completion = completion
        )
    }

    /**
     * @param markedConversationIDs 需要去掉“标记未读”的会话；去标记失败（例如套餐不支持会话标记）时仍会继续清未读数。
     */
    fun clearUnread(
        store: ConversationListStore,
        conversationIDs: List<String>,
        markedConversationIDs: Collection<String> = conversationIDs,
        completion: CompletionHandler? = null
    ) {
        val ids = conversationIDs.filter { it.isNotEmpty() }.distinct()
        if (ids.isEmpty()) {
            completion?.onSuccess()
            return
        }
        val marked = markedConversationIDs.filter { it.isNotEmpty() }.distinct()
        unmark(store, marked, 0) { clearCounts(store, ids, completion) }
    }

    /**
     * 清空聊天记录，并把这个会话的未读数、“标记未读”一起清掉。
     * 清空聊天记录本身不会动未读：会话被标为未读后清空记录，未读数/红点会一直留着。
     * [completion] 反映清空聊天记录的结果；清未读是随后尽力而为，不影响它。
     */
    fun clearMessages(
        store: ConversationListStore,
        conversationID: String,
        completion: CompletionHandler? = null
    ) {
        store.clearConversationMessages(conversationID, object : CompletionHandler {
            override fun onSuccess() {
                completion?.onSuccess()
                clearUnread(store, listOf(conversationID))
            }

            override fun onFailure(code: Int, desc: String) {
                completion?.onFailure(code, desc)
            }
        })
    }

    private fun unmark(
        store: ConversationListStore,
        conversationIDs: List<String>,
        start: Int,
        onFinished: () -> Unit
    ) {
        if (start >= conversationIDs.size) {
            onFinished()
            return
        }
        val end = minOf(start + UNMARK_BATCH_SIZE, conversationIDs.size)
        store.markConversation(
            conversationIDs.subList(start, end),
            ConversationMarkType.unread,
            false,
            object : CompletionHandler {
                override fun onSuccess() {
                    unmark(store, conversationIDs, end, onFinished)
                }

                override fun onFailure(code: Int, desc: String) {
                    onFinished()
                }
            }
        )
    }

    private fun clearCounts(
        store: ConversationListStore,
        conversationIDs: List<String>,
        completion: CompletionHandler?
    ) {
        val remaining = AtomicInteger(conversationIDs.size)
        val failure = AtomicReference<Pair<Int, String>?>(null)
        val finishOne = {
            if (remaining.decrementAndGet() == 0) {
                val error = failure.get()
                if (error == null) completion?.onSuccess() else completion?.onFailure(error.first, error.second)
            }
        }
        conversationIDs.forEach { conversationID ->
            store.clearConversationUnreadCount(conversationID, object : CompletionHandler {
                override fun onSuccess() {
                    finishOne()
                }

                override fun onFailure(code: Int, desc: String) {
                    failure.compareAndSet(null, code to desc)
                    finishOne()
                }
            })
        }
    }
}
