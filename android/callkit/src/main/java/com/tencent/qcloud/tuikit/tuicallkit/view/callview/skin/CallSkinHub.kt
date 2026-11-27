package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.content.Context
import com.tencent.qcloud.tuikit.tuicallkit.R
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Local state of the call-page entertainment layer (topic card, gift banner) plus the request to open the sound /
 * beauty panel, which the call view hosts ([CallEffectsPanel]).
 *
 * Nothing here changes the SDK call state (connect / end / duration). The gift is the exception to "local only": it is
 * handed to [CallGiftBridge] so the host can send it as a real custom message and the peer's page can show it too.
 */
class CallSkinHub(private val context: Context) {
    private val topicRes = intArrayOf(
        R.string.callskin_topic_1, R.string.callskin_topic_2, R.string.callskin_topic_3, R.string.callskin_topic_4,
        R.string.callskin_topic_5, R.string.callskin_topic_6, R.string.callskin_topic_7, R.string.callskin_topic_8,
        R.string.callskin_topic_9, R.string.callskin_topic_10, R.string.callskin_topic_11, R.string.callskin_topic_12
    )
    private val topicTitleRes = intArrayOf(
        R.string.callskin_topic_title_1, R.string.callskin_topic_title_2, R.string.callskin_topic_title_3, R.string.callskin_topic_title_4,
        R.string.callskin_topic_title_5, R.string.callskin_topic_title_6, R.string.callskin_topic_title_7, R.string.callskin_topic_title_8,
        R.string.callskin_topic_title_9, R.string.callskin_topic_title_10, R.string.callskin_topic_title_11, R.string.callskin_topic_title_12
    )

    /** Each call starts on a different topic, so two calls in a row do not open with the same question. */
    var topicIndex = topicRes.indices.random()
        private set
    var topicVisible = false
        private set
    var giftCombo = 0
        private set
    private var giftToastShown = false

    private val topicListeners = CopyOnWriteArrayList<() -> Unit>()
    private val giftListeners = CopyOnWriteArrayList<(Int) -> Unit>()
    private val peerGiftListeners = CopyOnWriteArrayList<(String, Int) -> Unit>()
    var peerGiftCombo = 0
        private set

    val topicText: String get() = context.getString(topicRes[topicIndex % topicRes.size])
    val topicTitle: String get() = context.getString(topicTitleRes[topicIndex % topicTitleRes.size])
    val giftName: String get() = context.getString(R.string.callskin_gift_name)

    fun addTopicListener(listener: () -> Unit) { topicListeners += listener }
    fun removeTopicListener(listener: () -> Unit) { topicListeners -= listener }
    fun addGiftListener(listener: (Int) -> Unit) { giftListeners += listener }
    fun removeGiftListener(listener: (Int) -> Unit) { giftListeners -= listener }
    fun addPeerGiftListener(listener: (String, Int) -> Unit) { peerGiftListeners += listener }
    fun removePeerGiftListener(listener: (String, Int) -> Unit) { peerGiftListeners -= listener }

    fun nextTopic() {
        topicIndex = (topicIndex + 1) % topicRes.size
        topicListeners.forEach { it() }
    }

    fun toggleTopic() {
        topicVisible = !topicVisible
        topicListeners.forEach { it() }
    }

    fun showTopic(visible: Boolean) {
        topicVisible = visible
        topicListeners.forEach { it() }
    }

    /** Set by the call view; opens the sound-effect or beauty sheet above the whole call page. */
    var panelOpener: ((CallEffectsPanel.Kind) -> Unit)? = null

    fun openPanel(kind: CallEffectsPanel.Kind) {
        panelOpener?.invoke(kind)
    }

    fun peerId(): String? = runCatching {
        val self = CallStore.shared.observerState.selfInfo.value.id
        CallStore.shared.observerState.allParticipants.value.firstOrNull { it.id != self }?.id
    }.getOrNull()

    fun sendGift(onFailed: () -> Unit = {}): Boolean {
        giftCombo += 1
        giftListeners.forEach { it(giftCombo) }
        val sender = CallGiftBridge.sender
        val peer = peerId()
        if (sender != null && !peer.isNullOrBlank()) sender(peer) { ok -> if (!ok) onFailed() }
        val first = !giftToastShown
        giftToastShown = true
        return first
    }

    fun receivePeerGift(name: String) {
        peerGiftCombo += 1
        peerGiftListeners.forEach { it(name, peerGiftCombo) }
    }
}
