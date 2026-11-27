package io.trtc.tuikit.chat.demo.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallGiftBridge
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.message.MessageInputStore
import io.trtc.tuikit.atomicxcore.api.message.SendMessagePayload
import io.trtc.tuikit.chat.demo.mock.DemoFixtures
import io.trtc.tuikit.chat.demo.social.DemoCardProtocol

object DemoCallGift {
    private const val CALL_GIFT_REF = "star_candy"
    private val main = Handler(Looper.getMainLooper())

    fun install(context: Context) {
        val app = context.applicationContext
        CallGiftBridge.sender = { peerId, onResult ->
            val gifts = runCatching { DemoFixtures.chat(app).giftPanel?.gifts }.getOrNull().orEmpty()
            val gift = gifts.firstOrNull { it.ref == CALL_GIFT_REF } ?: gifts.firstOrNull()
            val data = gift?.let { runCatching { DemoCardProtocol.build("gift", DemoGiftCard.payload(it)) }.getOrNull() }
            if (data == null) {
                main.post { onResult(false) }
            } else {
                MessageInputStore.create("c2c_$peerId").sendMessage(
                    SendMessagePayload.CustomSendMessagePayload(data, DemoGiftCard.SUMMARY, null),
                    null,
                    object : CompletionHandler {
                        override fun onSuccess() { main.post { onResult(true) } }
                        override fun onFailure(code: Int, desc: String) { main.post { onResult(false) } }
                    }
                )
            }
        }
        CallGiftBridge.inspector = { customData ->
            DemoCardProtocol.parse(customData)?.takeIf { it.kind == "gift" }?.let { it.payload["name"].orEmpty() }
        }
    }
}
