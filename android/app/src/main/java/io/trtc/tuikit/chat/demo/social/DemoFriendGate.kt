package io.trtc.tuikit.chat.demo.social

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.contact.ContactInfo
import io.trtc.tuikit.atomicxcore.api.contact.ContactStore
import io.trtc.tuikit.atomicxcore.api.contact.GetContactInfoCompletionHandler
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.home.FriendAddOutcome
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.SocialToast

object DemoFriendGate {
    private val main = Handler(Looper.getMainLooper())

    /** IM returns this when the target needs to approve; the request itself was delivered. */
    private const val ERR_NEED_CONFIRM = 30539

    fun check(peer: String, onResult: (ContactInfo?) -> Unit) {
        if (peer.isBlank()) {
            onResult(null)
            return
        }
        ContactStore.shared.getContactInfo(
            userIDList = listOf(peer),
            completion = object : GetContactInfoCompletionHandler {
                override fun onSuccess(contactInfoList: List<ContactInfo>) {
                    main.post { onResult(contactInfoList.firstOrNull()) }
                }

                override fun onFailure(code: Int, desc: String) {
                    main.post { onResult(null) }
                }
            }
        )
    }

    /**
     * Sends the preset friend request in one tap: no remark, fixed verification wording.
     * Toasts the outcome here so the profile page and the chat settings row behave the same.
     */
    fun add(context: Context, peer: String, onResult: (FriendAddOutcome) -> Unit = {}) {
        if (peer.isBlank()) {
            toast(context, DemoText.get(R.string.demo_friend_request_failed), SocialToast.Kind.ERROR)
            onResult(FriendAddOutcome.FAILED)
            return
        }
        ContactStore.shared.addFriend(
            userID = peer,
            remark = null,
            addWording = DemoText.get(R.string.demo_friend_request_wording),
            completion = object : CompletionHandler {
                override fun onSuccess() {
                    main.post {
                        toast(context, DemoText.get(R.string.demo_friend_added), SocialToast.Kind.SUCCESS)
                        onResult(FriendAddOutcome.ADDED)
                    }
                }

                override fun onFailure(code: Int, desc: String) {
                    main.post {
                        if (code == ERR_NEED_CONFIRM) {
                            toast(context, DemoText.get(R.string.demo_friend_request_sent), SocialToast.Kind.SUCCESS)
                            onResult(FriendAddOutcome.PENDING)
                        } else {
                            HostDiagnostics.record("friend.add", code, desc)
                            toast(context, DemoText.get(R.string.demo_friend_request_failed), SocialToast.Kind.ERROR)
                            onResult(FriendAddOutcome.FAILED)
                        }
                    }
                }
            }
        )
    }

    /** Removes [peer] from the friend list; the callback runs on the main thread. */
    fun delete(peer: String, onResult: (Boolean) -> Unit) {
        if (peer.isBlank()) {
            onResult(false)
            return
        }
        ContactStore.shared.deleteFriend(peer, object : CompletionHandler {
            override fun onSuccess() {
                main.post { onResult(true) }
            }

            override fun onFailure(code: Int, desc: String) {
                main.post { onResult(false) }
            }
        })
    }

    private fun toast(context: Context, text: String, kind: SocialToast.Kind) {
        SocialToast.show(context, text, kind)
    }
}
