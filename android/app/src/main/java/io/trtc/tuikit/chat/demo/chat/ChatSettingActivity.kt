package io.trtc.tuikit.chat.demo.chat

import io.trtc.tuikit.chat.hostbase.SocialToast
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.mock.DemoChatSetting
import io.trtc.tuikit.chat.demo.mock.DemoFixtures
import io.trtc.tuikit.chat.demo.social.DemoFriendGate
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.uikit.components.chatsetting.config.C2CChatSettingConfig
import io.trtc.tuikit.chat.uikit.components.chatsetting.model.C2CSceneExtras
import io.trtc.tuikit.chat.uikit.components.chatsetting.ui.C2CChatSettingView

/**
 * S6 单聊设置. Mute, pin, blacklist, clear history and the chat background are the real IM
 * capabilities of the Chat UIKit; intimacy, nickname and report rows are host content
 * (design/fixtures/chat.json `chatSetting`) and never submit a business request.
 */
class ChatSettingActivity : DemoActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val peer = intent.getStringExtra("peerId").orEmpty()
        if (peer.isBlank()) {
            finish()
            return
        }
        val copy: DemoChatSetting = runCatching { DemoFixtures.chat(this).chatSetting }.getOrNull()
            ?: DemoChatSetting(DemoText.get(R.string.demo_chat_settings), emptyList(), DemoText.get(R.string.demo_relationship), "", DemoText.get(R.string.demo_chat_background), DemoText.get(R.string.demo_custom_nickname), "", DemoText.get(R.string.demo_report_them), "", "")

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(DemoUi.tokens.bgColorTopBar)
        }
        setContentView(root)
        immersive(root, DemoUi.tokens.bgColorTopBar, bodyColor = DemoUi.tokens.bgColorTopBar)
        root.addView(header(copy.title))

        DemoFriendGate.check(peer) { info ->
            if (isFinishing || isDestroyed) return@check
            val view = C2CChatSettingView(this)
            view.setup(
                userID = peer,
                onContactDeleted = {
                    setResult(RESULT_OK)
                    finish()
                },
                config = C2CChatSettingConfig(
                    isShowRemark = false,
                    isShowSendMessage = false,
                    isShowVoiceCall = false,
                    isShowVideoCall = false,
                    isShowDeleteFriend = false,
                ),
                sceneExtras = C2CSceneExtras(
                    profileTagView = { ctx ->
                        io.trtc.tuikit.chat.hostbase.Host.verifiedTag(
                            ctx, DemoText.get(io.trtc.tuikit.chat.hostbase.R.string.demo_verified)
                        )
                    },
                    intimacyLabel = copy.intimacyLabel,
                    intimacyBadge = copy.intimacyBadge,
                    backgroundLabel = copy.backgroundLabel,
                    nicknameLabel = copy.nicknameLabel,
                    nicknameValue = copy.nicknameValue,
                    reportLabel = copy.reportLabel,
                    footer = copy.footer,
                    addFriendLabel = if (info?.isFriend == true) null else DemoText.get(R.string.demo_add_friend),
                    onAddFriendClick = {
                        DemoFriendGate.add(this, peer)
                    },
                    deleteFriendLabel = if (info?.isFriend == true) DemoText.get(R.string.demo_delete_friend) else null,
                    onMockRowClick = {
                        SocialToast.show(this, copy.mockNotice.ifBlank { DemoText.get(R.string.demo_demo_mock_demo_item) })
                    }
                )
            )
            root.addView(view, LinearLayout.LayoutParams(-1, 0, 1f))
        }
    }

    /** Prototype `.pageheader--bordered`: back, centred title, 1px bottom border. */
    private fun header(title: String): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(Color.parseColor(DemoUi.BAR))
        addView(FrameLayout(this@ChatSettingActivity).apply {
            addView(Host.backButton(this@ChatSettingActivity) { finish() }, FrameLayout.LayoutParams(-2, -2,
                Gravity.START or Gravity.CENTER_VERTICAL).apply { marginStart = DemoUi.dp(this@ChatSettingActivity, HostMetrics.BACK_BUTTON_MARGIN) })
            addView(DemoUi.text(this@ChatSettingActivity, title, 17f, DemoUi.TEXT, true).apply {
                gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
        }, LinearLayout.LayoutParams(-1, DemoUi.dp(this@ChatSettingActivity, 52)))
        addView(android.view.View(this@ChatSettingActivity).apply {
            setBackgroundColor(DemoUi.tokens.strokeColorSecondary)
        }, LinearLayout.LayoutParams(-1, 1))
    }
}
