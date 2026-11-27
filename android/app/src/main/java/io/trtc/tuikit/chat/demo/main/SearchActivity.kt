package io.trtc.tuikit.chat.demo.main

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import io.trtc.tuikit.chat.demo.chat.ChatActivity
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.uikit.components.search.ui.SearchView

/**
 * Messages-tab search: the UIKit global search (friends, groups, messages) on a full page of its own.
 * A friend or a conversation opens that chat; a message hit opens the chat and scrolls to the message.
 */
class SearchActivity : DemoActivity() {
    private var callReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        callReady = intent.getBooleanExtra("callReady", false)
        val root = FrameLayout(this)
        setContentView(root)
        immersive(root, DemoUi.tokens.bgColorOperate, bodyColor = DemoUi.tokens.bgColorOperate)
        val search = SearchView(this)
        search.setup(
            onContactSelect = { friend ->
                val name = friend.friendRemark?.takeIf { it.isNotBlank() } ?: friend.userInfo?.nickname?.takeIf { it.isNotBlank() } ?: friend.userID
                openChat("c2c_${friend.userID}", name)
            },
            onGroupSelect = { group -> openChat("group_${group.groupID}", group.groupName.orEmpty()) },
            onConversationSelect = { item -> openChat(item.conversationID, item.conversationShowName) },
            onMessageSelect = { message ->
                val conversation = search.currentConversation() ?: return@setup
                DemoSearchLocate.put(conversation.conversationID, message)
                openChat(conversation.conversationID, conversation.conversationShowName)
            },
            onBack = { finish() }
        )
        root.addView(search, FrameLayout.LayoutParams(-1, -1))
    }

    private fun openChat(conversationId: String, name: String) {
        startActivity(Intent(this, ChatActivity::class.java)
            .putExtra("conversationId", conversationId)
            .putExtra("peerName", name)
            .putExtra("callReady", callReady))
    }
}

/** A search hit waiting for the chat page that will scroll to it (the message is not parcelable, so it travels here). */
object DemoSearchLocate {
    @Volatile
    private var pending: Pair<String, MessageInfo>? = null

    fun put(conversationId: String, message: MessageInfo) {
        pending = conversationId to message
    }

    fun take(conversationId: String): MessageInfo? {
        val hit = pending ?: return null
        pending = null
        return hit.second.takeIf { hit.first == conversationId }
    }
}
