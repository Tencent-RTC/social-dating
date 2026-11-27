package io.trtc.tuikit.chat.demo.host

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.widget.EditText
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import io.trtc.tuikit.chat.demo.DemoSession
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.chat.ChatActivity
import io.trtc.tuikit.chat.demo.login.DemoLoginStore
import io.trtc.tuikit.chat.demo.login.FriendAddRuleSheet
import io.trtc.tuikit.chat.demo.login.LoginActivity
import io.trtc.tuikit.chat.demo.login.LoginAppearanceSheet
import io.trtc.tuikit.chat.demo.login.LoginLanguageSheet
import io.trtc.tuikit.chat.demo.social.DemoBadgeCenter
import io.trtc.tuikit.chat.demo.social.DemoCallPromoter
import io.trtc.tuikit.chat.demo.social.DemoFriendGate
import io.trtc.tuikit.chat.demo.social.DemoGroupWatcher
import io.trtc.tuikit.chat.demo.social.DemoMessageBanner
import io.trtc.tuikit.chat.demo.social.DemoSessionBindings
import io.trtc.tuikit.chat.home.FriendAddOutcome
import io.trtc.tuikit.chat.home.HomeActions
import io.trtc.tuikit.chat.home.data.HomeProfilePost
import io.trtc.tuikit.chat.home.data.HomeUserCard
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.hostbase.SocialToast
import io.trtc.tuikit.chat.mine.MineActions
import io.trtc.tuikit.chat.mine.data.MineMenuItem
import io.trtc.tuikit.chat.uikit.components.common.AtomicCallEventPublisher

object DemoHomeActions : HomeActions {
    override fun onOpenChat(context: Context, user: HomeUserCard) {
        resolvePeer(context, user, onCancel = {}) { peer ->
            DemoGroupWatcher.noteReplied("c2c_$peer")
            openChat(context, peer, user)
        }
    }

    override fun onAddFriend(context: Context, user: HomeUserCard, onResult: (FriendAddOutcome) -> Unit) {
        val peer = DemoSessionBindings.peerOf(user.id) ?: user.userId
        DemoFriendGate.add(context, peer, onResult)
    }

    override fun isFriend(context: Context, user: HomeUserCard, onResult: (Boolean) -> Unit) {
        val peer = DemoSessionBindings.peerOf(user.id) ?: user.userId
        DemoFriendGate.check(peer) { info -> onResult(info?.isFriend == true) }
    }

    override fun onDeleteFriend(context: Context, user: HomeUserCard, onResult: (Boolean) -> Unit) {
        val peer = DemoSessionBindings.peerOf(user.id) ?: user.userId
        if (peer.isBlank()) return onResult(false)
        DemoFriendGate.delete(peer) { deleted ->
            if (deleted) {
                toast(context, DemoText.get(R.string.demo_friend_deleted), SocialToast.Kind.SUCCESS)
            } else {
                toast(context, DemoText.get(R.string.demo_delete_friend_failed), SocialToast.Kind.ERROR)
            }
            onResult(deleted)
        }
    }

    override fun onVideoChat(context: Context, user: HomeUserCard) {
        resolvePeer(context, user, onCancel = {}) { peer ->
            if (!DemoSession.callReady) {
                HostDiagnostics.record("home.call", 0, "call component not ready")
                toast(context, DemoText.get(BaseR.string.demo_call_sdk_is_not_ready_please_log), SocialToast.Kind.WARNING)
            } else {
                AtomicCallEventPublisher.publishStartCall(
                    listOf(peer),
                    AtomicCallEventPublisher.MEDIA_TYPE_VIDEO
                )
            }
        }
    }

    override fun onVoiceSignatureClick(context: Context, user: HomeUserCard) =
        toast(context, DemoText.get(R.string.demo_the_voice_signature_is_a_demo_no))

    override fun onMoreClick(context: Context, user: HomeUserCard) =
        toast(context, DemoText.get(R.string.demo_more_report_block_are_demo_entries_and))

    override fun onAlbumPhotoClick(context: Context, user: HomeUserCard, photo: String) =
        toast(context, DemoText.get(R.string.demo_demo_album_design_sample_images_only))

    override fun onCommentClick(context: Context, user: HomeUserCard, post: HomeProfilePost) =
        toast(context, DemoText.get(R.string.demo_comment_demo_placeholder))

    private fun resolvePeer(context: Context, user: HomeUserCard, onCancel: () -> Unit, then: (String) -> Unit) {
        val bound = DemoSessionBindings.peerOf(user.id) ?: user.userId
        if (bound.isNotBlank()) return then(bound)
        val activity = context as? Activity ?: return onCancel()
        val input = EditText(activity).apply {
            hint = DemoText.get(R.string.demo_real_test_userid_bound_to_this_mock)
            inputType = InputType.TYPE_CLASS_TEXT
            setSingleLine()
        }
        Host.showThemed(activity, AlertDialog.Builder(activity)
            .setTitle(DemoText.get(R.string.demo_demo_account_not_configured))
            .setMessage(DemoText.get(R.string.demo_demo_mock_is_a_local_mock_person, user.displayName))
            .setView(input)
            .setNegativeButton(DemoText.get(BaseR.string.demo_cancel)) { _, _ -> onCancel() }
            .setOnCancelListener { onCancel() }
            .setPositiveButton(DemoText.get(R.string.demo_bind_and_chat)) { _, _ ->
                val peer = input.text.toString().trim()
                if (peer.isEmpty() || peer == DemoSession.accountId) {
                    toast(context, DemoText.get(R.string.demo_enter_another_real_test_account), SocialToast.Kind.WARNING)
                    onCancel()
                } else {
                    DemoSessionBindings.bind(user.id, peer)
                    then(peer)
                }
            })
    }

    private fun openChat(context: Context, peer: String, user: HomeUserCard) {
        context.startActivity(Intent(context, ChatActivity::class.java)
            .putExtra("peerId", peer)
            .putExtra("peerName", user.displayName)
            .putExtra("callReady", DemoSession.callReady))
    }

    private fun toast(context: Context, message: String, kind: SocialToast.Kind = SocialToast.Kind.DEFAULT) =
        SocialToast.show(context, message, kind)
}

object DemoMineActions : MineActions {
    override fun onWalletClick(context: Context) =
        toast(context, DemoText.get(R.string.demo_wallet_balance_and_top_up))

    override fun onMenuItemClick(context: Context, item: MineMenuItem) =
        toast(context, item.title)

    override fun onEditProfileClick(context: Context): Boolean {
        if (!DemoSession.preview) return true
        toast(context, DemoText.get(R.string.demo_edit_profile_needs_login), SocialToast.Kind.WARNING)
        return false
    }

    override fun isLogoutAvailable(): Boolean = !DemoSession.preview

    override fun showLanguagePicker(activity: Activity, onApplied: () -> Unit) {
        LoginLanguageSheet(activity, onApplied).show()
    }

    override fun showAppearancePicker(activity: Activity, onApplied: () -> Unit) {
        LoginAppearanceSheet(activity, onApplied).show()
    }

    override fun showFriendAddRulePicker(activity: Activity, onApplied: () -> Unit) {
        FriendAddRuleSheet(activity, onApplied).show()
    }

    /** Signs out of IM first; only when that succeeds is the local session dropped and the login page shown. */
    override fun onLogout(context: Context) {
        val app = context.applicationContext
        LoginStore.shared.logout(object : CompletionHandler {
            override fun onSuccess() {
                Handler(Looper.getMainLooper()).post { finishLogout(app) }
            }

            override fun onFailure(code: Int, desc: String) {
                HostDiagnostics.record("mine.logout", code, desc)
                Handler(Looper.getMainLooper()).post { toast(app, DemoText.get(R.string.demo_log_out_failed), SocialToast.Kind.ERROR) }
            }
        })
    }

    fun finishLogout(app: Context, notice: String? = null) {
        DemoCallPromoter.stop()
        DemoGroupWatcher.stop()
        DemoMessageBanner.stop()
        DemoBadgeCenter.stop()
        DemoSessionBindings.reset()
        DemoSession.accountId = ""
        DemoSession.callReady = false
        DemoSession.preview = false
        DemoLoginStore.clear()
        val intent = Intent(app, LoginActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (notice != null) intent.putExtra(LoginActivity.EXTRA_SESSION_NOTICE, notice)
        app.startActivity(intent)
    }

    private fun toast(context: Context, message: String, kind: SocialToast.Kind = SocialToast.Kind.DEFAULT) =
        SocialToast.show(context, message, kind)
}
