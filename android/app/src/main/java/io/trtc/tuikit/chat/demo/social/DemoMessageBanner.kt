package io.trtc.tuikit.chat.demo.social

import android.content.Context
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.tencent.imsdk.v2.V2TIMAdvancedMsgListener
import com.tencent.imsdk.v2.V2TIMConversation
import com.tencent.imsdk.v2.V2TIMManager
import com.tencent.imsdk.v2.V2TIMMessage
import com.tencent.imsdk.v2.V2TIMValueCallback
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationType
import io.trtc.tuikit.atomicxcore.api.message.AudioMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.CustomMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.FaceMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.FileMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.ImageMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.MergedMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import io.trtc.tuikit.atomicxcore.api.message.MessagePayload
import io.trtc.tuikit.atomicxcore.api.message.MessageSenderInfo
import io.trtc.tuikit.atomicxcore.api.message.MessageType
import io.trtc.tuikit.atomicxcore.api.message.StreamMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.TextMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.VideoMessagePayload
import io.trtc.tuikit.chat.demo.DemoSession
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.chat.ChatActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.HostNotifyPrefs
import io.trtc.tuikit.chat.hostbase.MsgBanner
import io.trtc.tuikit.chat.uikit.components.emojipicker.EmojiSpanHelper
import io.trtc.tuikit.chat.uikit.components.messagelist.typing.TypingMessageProtocol
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallMessageParser
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.MessageListMessageSummaryFormatter

object DemoMessageBanner {
    private const val SETTLE_MS = 120L
    private const val VIBRATE_MS = 40L
    private const val BANNER_SUMMARY_SP = 13f
    private const val C2C_PREFIX = "c2c_"

    private class Arrival(val conversationId: String, val message: MessageInfo)

    private val main = Handler(Looper.getMainLooper())
    private val detector = BannerDetector()
    private val pending = LinkedHashMap<String, Arrival>()
    private val flush = Runnable { flushPending() }
    private var account: String? = null
    private var appContext: Context? = null
    private var listener: V2TIMAdvancedMsgListener? = null
    private var formatter: MessageListMessageSummaryFormatter? = null

    @Volatile
    var onShown: (() -> Unit)? = null

    fun ensureStarted(context: Context, accountId: String) {
        if (listener != null && account == accountId) return
        stop()
        account = accountId
        appContext = context.applicationContext
        formatter = MessageListMessageSummaryFormatter()
        detector.reset()
        val created = object : V2TIMAdvancedMsgListener() {
            override fun onRecvNewMessage(msg: V2TIMMessage?) {
                msg ?: return
                main.post { onReceived(msg) }
            }
        }
        listener = created
        V2TIMManager.getMessageManager().addAdvancedMsgListener(created)
    }

    fun stop() {
        listener?.let { V2TIMManager.getMessageManager().removeAdvancedMsgListener(it) }
        listener = null
        account = null
        main.removeCallbacks(flush)
        pending.clear()
        detector.reset()
        MsgBanner.hide()
    }

    private fun onReceived(msg: V2TIMMessage) {
        if (listener == null || DemoSession.preview) return
        val peer = msg.userID.orEmpty()
        val isC2C = msg.groupID.isNullOrEmpty() && peer.isNotEmpty()
        val conversationId = if (isC2C) C2C_PREFIX + peer else ""
        val info = msg.toBannerMessageInfo()
        if (CallMessageParser.isCallMessage(info)) return
        val incoming = BannerIncoming(
            messageId = msg.msgID.orEmpty(),
            conversationId = conversationId,
            isC2C = isC2C,
            isSelf = msg.isSelf,
            timestampSeconds = msg.timestamp,
            excludedFromUnread = msg.isExcludedFromUnreadCount,
            isTyping = TypingMessageProtocol.isTypingMessage(info)
        )
        if (!detector.accept(incoming)) return
        pending[conversationId] = Arrival(conversationId, info)
        main.removeCallbacks(flush)
        main.postDelayed(flush, SETTLE_MS)
    }

    private fun flushPending() {
        val batch = pending.values.sortedBy { it.message.timestamp ?: 0L }
        pending.clear()
        batch.forEach { arrival ->
            V2TIMManager.getConversationManager().getConversation(arrival.conversationId, object : V2TIMValueCallback<V2TIMConversation> {
                override fun onSuccess(conversation: V2TIMConversation?) {
                    conversation ?: return
                    main.post { present(arrival, conversation) }
                }

                override fun onError(code: Int, desc: String?) {
                    HostDiagnostics.record("banner.conversation", code, desc.orEmpty())
                }
            })
        }
    }

    private fun present(arrival: Arrival, conversation: V2TIMConversation) {
        val app = appContext ?: return
        val summarizer = formatter ?: return
        if (listener == null || DemoSession.preview) return
        if (conversation.recvOpt != V2TIMMessage.V2TIM_RECEIVE_MESSAGE) return
        if (arrival.conversationId == DemoSession.activeConversationId) return
        val activity = MsgBanner.currentActivity ?: return
        if (CallStore.shared.observerState.selfInfo.value.status != CallParticipantStatus.None) return
        val summary = runCatching { summarizer.format(app, arrival.message, arrival.conversationId) }.getOrDefault("")
        if (summary.isBlank()) return
        val peer = arrival.conversationId.removePrefix(C2C_PREFIX)
        val title = conversation.showName?.takeIf { it.isNotBlank() }
            ?: DemoPeerProfiles.forUser(app, peer)?.name
            ?: peer
        val key = arrival.conversationId
        val model = MsgBanner.Model(
            key = key,
            title = title,
            // Names first (「[微笑]」), so nothing flashes a raw key; the pictures replace them once loaded.
            summary = EmojiSpanHelper.replaceEmojiKeysWithNames(summary),
            time = DemoText.get(R.string.demo_just_now),
            avatar = conversation.faceUrl
        )
        val shown = MsgBanner.show(model) {
            activity.startActivity(
                android.content.Intent(activity, ChatActivity::class.java)
                    .putExtra("conversationId", arrival.conversationId)
                    .putExtra("peerName", title)
                    .putExtra("callReady", DemoSession.callReady)
            )
        }
        if (!shown) return
        val textSizePx = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, BANNER_SUMMARY_SP,
            app.resources.displayMetrics)
        EmojiSpanHelper.applyEmojiSpans(app, summary, textSizePx, null) { spanned -> MsgBanner.updateSummary(key, spanned) }
        onShown?.invoke()
        alert(app)
    }

    private fun alert(app: Context) {
        val ringer = (app.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.ringerMode
        val decision = BannerAlertPolicy.decide(
            messageAlerts = HostNotifyPrefs.messageAlerts(app),
            soundEnabled = HostNotifyPrefs.sound(app),
            ringer = when (ringer) {
                AudioManager.RINGER_MODE_SILENT -> BannerAlertPolicy.Ringer.SILENT
                AudioManager.RINGER_MODE_VIBRATE -> BannerAlertPolicy.Ringer.VIBRATE
                else -> BannerAlertPolicy.Ringer.NORMAL
            }
        )
        if (decision.vibrate) runCatching { vibrate(app) }.onFailure { HostDiagnostics.record("banner.vibrate", 0, it.toString()) }
        if (decision.sound) runCatching {
            RingtoneManager.getRingtone(app, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))?.play()
        }.onFailure { HostDiagnostics.record("banner.sound", 0, it.toString()) }
    }

    private fun vibrate(app: Context) {
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            app.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createOneShot(VIBRATE_MS, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(VIBRATE_MS)
        }
    }
}

data class BannerIncoming(
    val messageId: String,
    val conversationId: String,
    val isC2C: Boolean,
    val isSelf: Boolean,
    val timestampSeconds: Long,
    val excludedFromUnread: Boolean,
    val isTyping: Boolean
)

class BannerDetector(
    private val now: () -> Long = { System.currentTimeMillis() },
    private val maxAgeSeconds: Long = MAX_AGE_SECONDS,
    private val memory: Int = MEMORY
) {
    private val seen = LinkedHashSet<String>()

    fun reset() {
        seen.clear()
    }

    fun accept(incoming: BannerIncoming): Boolean {
        if (incoming.messageId.isEmpty() || !seen.add(incoming.messageId)) return false
        while (seen.size > memory) seen.remove(seen.first())
        if (!isBannerWorthy(incoming)) return false
        return now() / 1000 - incoming.timestampSeconds <= maxAgeSeconds
    }

    private fun isBannerWorthy(m: BannerIncoming) =
        m.isC2C && m.conversationId.isNotEmpty() && !m.isSelf && !m.excludedFromUnread && !m.isTyping

    companion object {
        const val MAX_AGE_SECONDS = 20L
        const val MEMORY = 64
    }
}

object BannerAlertPolicy {
    enum class Ringer { SILENT, VIBRATE, NORMAL }

    data class Alert(val vibrate: Boolean, val sound: Boolean)

    fun decide(messageAlerts: Boolean, soundEnabled: Boolean, ringer: Ringer): Alert {
        if (!messageAlerts) return Alert(vibrate = false, sound = false)
        return when (ringer) {
            Ringer.SILENT -> Alert(vibrate = false, sound = false)
            Ringer.VIBRATE -> Alert(vibrate = true, sound = false)
            Ringer.NORMAL -> Alert(vibrate = true, sound = soundEnabled)
        }
    }
}

internal fun V2TIMMessage.toBannerMessageInfo(): MessageInfo {
    val senderId = sender.orEmpty()
    val senderAvatar = faceUrl.orEmpty()
    val senderNick = nickName.orEmpty()
    val senderRemark = friendRemark.orEmpty()
    val info = MessageInfo()
    info.msgID = msgID.orEmpty()
    info.timestamp = timestamp
    info.isSentBySelf = isSelf
    info.conversationType = if (groupID.isNullOrEmpty()) ConversationType.C2C else ConversationType.GROUP
    info.from = MessageSenderInfo().apply {
        userID = senderId
        avatarURL = senderAvatar
        nickname = senderNick
        friendRemark = senderRemark
    }
    val (type, payload) = bannerTypeAndPayload()
    info.messageType = type
    if (payload != null) info.messagePayload = payload
    return info
}

private fun V2TIMMessage.bannerTypeAndPayload(): Pair<MessageType, MessagePayload?> = when (elemType) {
    V2TIMMessage.V2TIM_ELEM_TYPE_TEXT -> MessageType.TEXT to TextMessagePayload().also {
        it.text = textElem?.text.orEmpty()
    }
    V2TIMMessage.V2TIM_ELEM_TYPE_CUSTOM -> MessageType.CUSTOM to CustomMessagePayload(
        customElem?.data?.let { String(it, Charsets.UTF_8) }.orEmpty(),
        customElem?.description.orEmpty(),
        customElem?.extension?.let { String(it, Charsets.UTF_8) }.orEmpty()
    )
    V2TIMMessage.V2TIM_ELEM_TYPE_IMAGE -> MessageType.IMAGE to ImageMessagePayload()
    V2TIMMessage.V2TIM_ELEM_TYPE_SOUND -> MessageType.AUDIO to AudioMessagePayload().also {
        it.audioDuration = soundElem?.duration ?: 0
    }
    V2TIMMessage.V2TIM_ELEM_TYPE_VIDEO -> MessageType.VIDEO to VideoMessagePayload()
    V2TIMMessage.V2TIM_ELEM_TYPE_FILE -> MessageType.FILE to FileMessagePayload().also {
        it.fileName = fileElem?.fileName.orEmpty()
    }
    V2TIMMessage.V2TIM_ELEM_TYPE_FACE -> MessageType.FACE to FaceMessagePayload()
    V2TIMMessage.V2TIM_ELEM_TYPE_MERGER -> MessageType.MERGED to MergedMessagePayload(
        mergerElem?.title.orEmpty(),
        mergerElem?.abstractList.orEmpty()
    )
    V2TIMMessage.V2TIM_ELEM_TYPE_STREAM -> MessageType.STREAM to StreamMessagePayload().also {
        it.markdown = streamElem?.markdown.orEmpty()
    }
    else -> MessageType.UNKNOWN to null
}
