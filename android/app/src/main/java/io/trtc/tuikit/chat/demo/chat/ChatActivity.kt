package io.trtc.tuikit.chat.demo.chat

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.ViewCompat
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.call.CallMediaType
import io.trtc.tuikit.atomicxcore.api.message.MessageInputStore
import io.trtc.tuikit.atomicxcore.api.message.SendMessagePayload
import io.trtc.tuikit.chat.demo.DemoSession
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.main.DemoSearchLocate
import io.trtc.tuikit.chat.demo.mock.DemoChatCopy
import io.trtc.tuikit.chat.demo.mock.DemoFixtures
import io.trtc.tuikit.chat.demo.mock.DemoMoreItem
import io.trtc.tuikit.chat.demo.mock.DemoQuickAction
import io.trtc.tuikit.chat.demo.mock.DemoQuickChip
import io.trtc.tuikit.chat.demo.social.DemoCardProtocol
import io.trtc.tuikit.chat.demo.social.DemoCardRolls
import io.trtc.tuikit.chat.demo.social.DemoChatSession
import io.trtc.tuikit.chat.demo.social.DemoGroupWatcher
import io.trtc.tuikit.chat.demo.social.DemoPeerProfile
import io.trtc.tuikit.chat.demo.social.DemoPeerProfiles
import io.trtc.tuikit.chat.demo.social.DemoQuickRowPolicy
import io.trtc.tuikit.chat.home.HomeKit
import io.trtc.tuikit.chat.home.data.HomeUserDetail
import io.trtc.tuikit.chat.home.ui.IcebreakerCard
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.hostbase.SocialToast
import io.trtc.tuikit.chat.hostbase.TagKind
import io.trtc.tuikit.chat.uikit.components.common.AtomicCallEventPublisher
import io.trtc.tuikit.chat.uikit.components.common.RtlUtils
import io.trtc.tuikit.chat.uikit.components.messageinput.config.ChatMessageInputConfig
import io.trtc.tuikit.chat.uikit.components.messageinput.config.MessageInputAppearance
import io.trtc.tuikit.chat.uikit.components.messageinput.config.MessageInputButtonAppearance
import io.trtc.tuikit.chat.uikit.components.messageinput.config.MessageInputFieldAppearance
import io.trtc.tuikit.chat.uikit.components.messageinput.config.MessageInputFill
import io.trtc.tuikit.chat.uikit.components.messageinput.data.MessageInputActionIDs
import io.trtc.tuikit.chat.uikit.components.messageinput.data.MessageInputMenuAction
import io.trtc.tuikit.chat.uikit.components.messageinput.data.MessageInputPanel
import io.trtc.tuikit.chat.uikit.components.messagelist.config.ChatMessageListConfig
import io.trtc.tuikit.chat.uikit.components.messagelist.config.MessageBubbleAppearance
import io.trtc.tuikit.chat.uikit.components.messagelist.config.MessageBubbleBackground
import io.trtc.tuikit.chat.uikit.components.messagelist.config.MessageBubbleCornerRadius
import io.trtc.tuikit.chat.uikit.pages.ChatPageView
import java.util.UUID

/**
 * 1v1 chat host (design S3/S4). Composes the copied native MessageList + MessageInput
 * and adds host chrome: centered header with call/more, a screen-level safety tip,
 * brand bubbles and the quick-interaction chip row.
 *
 * Real: messages, sender/direction/status, the chat.card CUSTOM transport, calls and
 * the greeting/recent routing. Local content: header subtitle, safety copy, chip/card content.
 */
class ChatActivity : DemoActivity() {
    private var conversationId = ""
    private var preview = false
    private var callReady = false
    private lateinit var copy: DemoChatCopy
    private val cardSender by lazy { MessageInputStore.create(conversationId) }

    /** Failed sends keep their ids so a retry is the same interaction (spec 03 §3). */
    private val pendingCards = mutableMapOf<String, Pair<String, String>>()
    private val sending = mutableSetOf<String>()
    private var chatPage: ChatPageView? = null
    private var currentPanel = MessageInputPanel.NONE
    private val quickSlots = linkedMapOf<String, QuickSlot>()
    private var giftDot: View? = null
    private var chipsOverlay: View? = null
    private var subtitleView: View? = null
    private var titleView: TextView? = null
    private var headerTitle: String = ""
    private var peerFixtureId: String? = null

    /** S6 finishes with RESULT_OK only when the friend was deleted, then the chat closes too. */
    private val chatSettingLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK) finish()
        }

    private class QuickSlot(val action: DemoQuickAction, val circle: FrameLayout, val icon: ImageView)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        conversationId = intent.getStringExtra("conversationId")
            ?: intent.getStringExtra("peerId")?.let { "c2c_$it" }
            ?: return finish()
        preview = intent.getBooleanExtra("previewChat", false)
        callReady = intent.getBooleanExtra("callReady", false)
        copy = runCatching { DemoFixtures.chat(this) }.getOrElse { DemoChatCopy("", DemoText.get(R.string.demo_1v1_chat), emptyList()) }

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        setContentView(root)
        // The chat header is bgColorOperate, so the status-bar strip takes that colour.
        immersive(root, DemoUi.tokens.bgColorOperate)
        val peerProfile = peerUserId()?.let { runCatching { DemoPeerProfiles.forUser(this, it) }.getOrNull() }
        val title = intent.getStringExtra("peerName").orEmpty().ifBlank { peerProfile?.name ?: peerUserId() ?: conversationId }
        peerFixtureId = peerProfile?.fixtureId
        root.addView(header(title, peerProfile))
        if (preview) root.addView(previewBanner())
        if (copy.safetyBanner.isNotBlank() && !DemoChatSession.isBannerDismissed(conversationId)) {
            root.addView(safetyBanner(copy.safetyBanner))
        }

        val chat = ChatPageView(this)
        chatPage = chat
        chat.setup(
            conversationID = conversationId,
            locateMessage = DemoSearchLocate.take(conversationId),
            messageListConfig = messageListConfig(),
            messageInputConfig = messageInputConfig(),
            onTextMessageSent = { onReplySent() },
            onTypingStatusChanged = { typing -> setPeerTyping(typing) },
            // The quick-interaction chips float above the list; hide them in multi-select so they do not cover
            // the forward / delete bar at the bottom.
            onMultiSelectStateChanged = { isMultiSelect -> chat.setMessageListFooterOverlayVisible(!isMultiSelect) }
        )
        chipsOverlay = if (copy.quickChips.isNotEmpty()) chipRow(copy.quickChips) else null
        chat.setMessageListFooterOverlay(chipsOverlay)
        installIcebreaker(chat)
        if (copy.quickActions.isNotEmpty()) {
            chat.setInputBottomAccessoryView(quickRow(copy.quickActions))
            chat.setOnInputPanelChangedListener { panel ->
                currentPanel = panel
                renderQuickRow()
            }
        }
        root.addView(chat, LinearLayout.LayoutParams(-1, 0, 1f))
    }

    /** Brand bubbles: own = violet gradient, incoming = raised dark surface (design S3). */
    private fun messageListConfig() = ChatMessageListConfig()
        // Design S3/S8 hides the own avatar; the peer avatar stays at the SDK default 40dp / 8dp gap.
        // The list's left/right switches are physical, so our own bubbles sit on the right in LTR and on the left in RTL.
        .apply {
            val rtl = RtlUtils.isLocaleRtl(this@ChatActivity)
            isShowLeftAvatar = !rtl
            isShowRightAvatar = rtl
        }
        .setOwnBubbleAppearance(
            MessageBubbleAppearance(
                background = MessageBubbleBackground.Gradient(
                    listOf(DemoUi.tokens.buttonColorPrimaryDefault, DemoUi.tokens.tagColorLevel4),
                    MessageBubbleBackground.GradientDirection.LEFT_RIGHT
                ),
                cornerRadius = MessageBubbleCornerRadius(topLeft = 18, topRight = 6, bottomRight = 18, bottomLeft = 18)
            )
        )
        .setIncomingBubbleAppearance(
            MessageBubbleAppearance(
                background = MessageBubbleBackground.Color(DemoUi.tokens.bgColorBubbleReciprocal),
                cornerRadius = MessageBubbleCornerRadius(topLeft = 6, topRight = 18, bottomRight = 18, bottomLeft = 18)
            )
        )
        .setCustomMessageRenderer(
            businessID = DemoCardProtocol.BUSINESS_ID,
            renderer = DemoCardRenderer(onReplay = ::replayCard),
            summaryProvider = DemoCardRenderer.summaryProvider
        )

    /**
     * Design E4 more panel: take-photo and record-video first (native logic, own tile bitmaps), then the 8 social
     * tiles; the native album, file and call actions are removed.
     */
    private fun messageInputConfig(): ChatMessageInputConfig {
        val quickRow = copy.quickActions.isNotEmpty()
        val config = if (quickRow) {
            ChatMessageInputConfig(isShowEmoji = false, isShowMore = false).setAppearance(inputAppearance())
        } else {
            ChatMessageInputConfig()
        }
        return config.customizeActions {
            if (copy.morePanel.isNotEmpty()) {
                replace(MessageInputActionIDs.TAKE_PHOTO) { it.copy(iconResID = R.drawable.demo_fn_camera, fullBleedIcon = true) }
                replace(MessageInputActionIDs.RECORD_VIDEO) { it.copy(iconResID = R.drawable.demo_fn_video, fullBleedIcon = true) }
                moveBefore(MessageInputActionIDs.TAKE_PHOTO, MessageInputActionIDs.ALBUM)
                moveBefore(MessageInputActionIDs.RECORD_VIDEO, MessageInputActionIDs.ALBUM)
            }
            copy.morePanel.forEach { item ->
                val tile = TILE_DRAWABLES[item.tile] ?: return@forEach
                insertBefore(MessageInputActionIDs.ALBUM, MessageInputMenuAction(
                    ID = "chat.more.${item.id}",
                    title = item.label,
                    iconResID = tile,
                    fullBleedIcon = true,
                    badgeText = item.badge,
                    onClick = { onMoreItem(item) }
                ))
            }
            if (copy.morePanel.isNotEmpty()) {
                listOf(MessageInputActionIDs.ALBUM, MessageInputActionIDs.FILE,
                    MessageInputActionIDs.VIDEO_CALL, MessageInputActionIDs.AUDIO_CALL)
                    .forEach { remove(it) }
            }
        }
    }

    private fun inputAppearance() = MessageInputAppearance(
        field = MessageInputFieldAppearance(
            fill = MessageInputFill.Color(DemoUi.tokens.bgColorInput),
            cornerRadiusDp = 18,
            minHeightDp = 40,
            hintText = copy.inputPlaceholder.ifBlank { null }
        ),
        audioRecordButton = MessageInputButtonAppearance(
            widthDp = 36,
            heightDp = 36,
            iconRes = R.drawable.demo_ic_mic,
            activeIconRes = R.drawable.demo_ic_keyboard,
            iconSizeDp = 26,
            iconTint = DemoUi.tokens.textColorSecondary,
            keepIconColors = true
        ),
        sendButton = MessageInputButtonAppearance(
            title = copy.sendText.ifBlank { DemoText.get(R.string.demo_send) },
            fill = MessageInputFill.Gradient(
                listOf(DemoUi.tokens.buttonColorPrimaryDefault, DemoUi.tokens.tagColorLevel4),
                MessageInputFill.GradientDirection.LEFT_RIGHT
            ),
            cornerRadiusDp = MessageInputButtonAppearance.CORNER_RADIUS_PILL,
            heightDp = 28,
            horizontalPaddingDp = 13,
            titleColor = Color.WHITE,
            titleSizeSp = 13f,
            titleBold = true
        )
    )

    private fun quickRow(actions: List<DemoQuickAction>) = LinearLayout(this).apply {
        setPadding(DemoUi.dp(this@ChatActivity, 6), 0, DemoUi.dp(this@ChatActivity, 6), DemoUi.dp(this@ChatActivity, 10))
        clipChildren = false
        clipToPadding = false
        actions.forEach { action ->
            addView(quickItem(action), LinearLayout.LayoutParams(0, DemoUi.dp(this@ChatActivity, 54), 1f))
        }
    }

    private fun quickItem(action: DemoQuickAction): View {
        val item = FrameLayout(this).apply {
            contentDescription = action.label
            clipChildren = false
            setOnClickListener { onQuickAction(action) }
        }
        if (action.primary) {
            item.addView(View(this).apply {
                background = GradientDrawable().apply {
                    setGradientType(GradientDrawable.RADIAL_GRADIENT)
                    setGradientRadius(DemoUi.dp(this@ChatActivity, 30).toFloat())
                    setColors(intArrayOf(androidx.core.graphics.ColorUtils.setAlphaComponent(DemoUi.tokens.tagColorLevel4, 0x70), androidx.core.graphics.ColorUtils.setAlphaComponent(DemoUi.tokens.tagColorLevel4, 0)))
                }
                translationY = DemoUi.dp(this@ChatActivity, 4).toFloat()
            }, FrameLayout.LayoutParams(DemoUi.dp(this, 64), DemoUi.dp(this, 64), Gravity.CENTER))
            val tile = FrameLayout(this).apply {
                clipChildren = false
                background = LayerDrawable(arrayOf<Drawable>(
                    GradientDrawable(GradientDrawable.Orientation.TL_BR,
                        intArrayOf(DemoUi.tokens.buttonColorPrimaryDefault, DemoUi.tokens.tagColorLevel4, DemoUi.tokens.tagColorLevel4)).apply {
                        cornerRadius = DemoUi.dp(this@ChatActivity, 14).toFloat() + 0.5f
                    },
                    GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                        intArrayOf(Host.alpha(Color.WHITE, 0.24f), Color.TRANSPARENT, Color.TRANSPARENT)).apply {
                        cornerRadius = DemoUi.dp(this@ChatActivity, 14).toFloat() + 0.5f
                        setStroke(DemoUi.dp(this@ChatActivity, 1), Host.alpha(Color.WHITE, 0.22f))
                    }
                ))
            }
            tile.addView(ImageView(this).apply {
                setImageResource(QUICK_DRAWABLES[action.icon] ?: 0)
            }, FrameLayout.LayoutParams(DemoUi.dp(this, 28), DemoUi.dp(this, 28), Gravity.CENTER))
            if (action.dot && !DemoChatSession.isGiftDotSeen()) {
                val dot = View(this).apply {
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(DemoUi.tokens.textColorError)
                        setStroke((DemoUi.dp(this@ChatActivity, 3) / 2), DemoUi.tokens.bgColorOperate)
                    }
                    translationY = -DemoUi.dp(this@ChatActivity, 1).toFloat()
                }
                giftDot = dot
                tile.addView(dot, FrameLayout.LayoutParams(DemoUi.dp(this, 9), DemoUi.dp(this, 9), Gravity.TOP or Gravity.END).apply {
                    marginEnd = DemoUi.dp(this@ChatActivity, 2)
                })
            }
            item.addView(tile, FrameLayout.LayoutParams(DemoUi.dp(this, 44), DemoUi.dp(this, 44), Gravity.CENTER))
        } else {
            val circle = FrameLayout(this)
            val icon = ImageView(this).apply { setImageResource(QUICK_DRAWABLES[action.icon] ?: 0) }
            circle.addView(icon, FrameLayout.LayoutParams(DemoUi.dp(this, 32), DemoUi.dp(this, 32), Gravity.CENTER))
            item.addView(circle, FrameLayout.LayoutParams(DemoUi.dp(this, 40), DemoUi.dp(this, 40), Gravity.CENTER))
            quickSlots[action.id] = QuickSlot(action, circle, icon)
        }
        return item
    }

    private fun renderQuickRow() {
        quickSlots.values.forEach { slot ->
            val on = DemoQuickRowPolicy.isOn(slot.action.id, currentPanel)
            slot.circle.background = if (on) GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(androidx.core.graphics.ColorUtils.setAlphaComponent(DemoUi.tokens.buttonColorPrimaryDefault, 0x33))
            } else null
            val name = if (DemoQuickRowPolicy.iconState(slot.action.id, currentPanel) == "on") {
                slot.action.iconOn ?: slot.action.icon
            } else {
                slot.action.icon
            }
            QUICK_DRAWABLES[name]?.let { slot.icon.setImageResource(it) }
        }
    }

    private fun onQuickAction(action: DemoQuickAction) {
        val chat = chatPage ?: return
        if (DemoQuickRowPolicy.collapsesPanelFirst(action.id, currentPanel)) chat.collapseInputPanels()
        when (action.action) {
            "album" -> if (preview) {
                toast(DemoText.get(R.string.demo_preview_mode_not_logged_in_image_not), SocialToast.Kind.WARNING)
            } else if (!chat.pickAlbumAndSend()) {
                toast(DemoText.get(R.string.demo_album_entry_is_unavailable), SocialToast.Kind.WARNING)
            }
            "call" -> chooseCall()
            "card" -> {
                if (action.dot) {
                    DemoChatSession.markGiftDotSeen()
                    giftDot?.visibility = View.GONE
                }
                sendDemoCard(action.id, action.kind, action.summary, action.payload)
            }
            "gift" -> {
                if (action.dot) {
                    DemoChatSession.markGiftDotSeen()
                    giftDot?.visibility = View.GONE
                }
                openGiftPanel()
            }
            "emoji" -> chat.toggleEmojiPanel()
            "more" -> chat.toggleMorePanel()
        }
    }

    /** Gift chooser: every tap sends one real chat.card gift; combo / hearts are local decoration. */
    private fun openGiftPanel() {
        val panel = copy.giftPanel?.takeIf { it.gifts.isNotEmpty() } ?: return
        GiftPanelDialog(this, panel) { gift, done ->
            sendDemoCard(
                key = DemoGiftCard.key(gift),
                kind = "gift",
                summary = DemoGiftCard.SUMMARY,
                payload = DemoGiftCard.payload(gift)
            ) { instanceId ->
                done(instanceId?.let { DemoGiftCombo.register(it, gift.ref, System.currentTimeMillis(), panel.comboWindowMs) })
            }
        }.show()
    }

    private fun chooseCall() {
        if (peerUserId() == null) {
            toast(DemoText.get(R.string.demo_audio_and_video_calls_are_only_available), SocialToast.Kind.WARNING)
            return
        }
        CallChoiceDialog(
            this,
            onVideo = { startCall(CallMediaType.Video) },
            onAudio = { startCall(CallMediaType.Audio) }
        ).show()
    }

    /** S6: real IM settings (mute / pin / blacklist / clear) with host demo rows, see ChatSettingActivity. */
    private fun openChatSettings() {
        val peer = peerUserId()
        if (peer == null || preview) {
            toast(if (preview) DemoText.get(R.string.demo_preview_mode_not_logged_in_cannot_open) else DemoText.get(R.string.demo_chat_settings_are_only_available_in_one), SocialToast.Kind.WARNING)
            return
        }
        chatSettingLauncher.launch(Intent(this, ChatSettingActivity::class.java)
            .putExtra("peerId", peer)
            .putExtra("peerName", intent.getStringExtra("peerName").orEmpty()))
    }

    private fun onMoreItem(item: DemoMoreItem) {
        when (item.action) {
            "card" -> sendDemoCard(item.id, item.kind, item.summary, DemoCardRolls.rolled(item.kind, item.payload))
            else -> toast(item.notice.ifBlank { DemoText.get(R.string.demo_demo_placeholder, item.label) })
        }
    }

    private fun header(title: String, profile: DemoPeerProfile?) = FrameLayout(this).apply {
        setBackgroundColor(DemoUi.tokens.bgColorOperate)
        minimumHeight = DemoUi.dp(this@ChatActivity, 52)
        addView(Host.backButton(this@ChatActivity) { finish() }, FrameLayout.LayoutParams(-2, -2,
            Gravity.START or Gravity.CENTER_VERTICAL).apply { marginStart = DemoUi.dp(this@ChatActivity, HostMetrics.BACK_BUTTON_MARGIN) })
        addView(LinearLayout(this@ChatActivity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            headerTitle = title
            addView(DemoUi.text(this@ChatActivity, title, 16f, DemoUi.TEXT, true).apply {
                gravity = Gravity.CENTER
                maxLines = 1
                titleView = this
            })
            addView(FrameLayout(this@ChatActivity).apply {
                // Accounts without a demo profile (real user IDs such as 100480) have no city / age / height, so the
                // row falls back to a neutral 「未知」 pill — the old "1v1 会话" line said nothing about the peer.
                val plain: View = LinearLayout(this@ChatActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER
                    fun addChip(text: String, accent: Int, textColor: Int = DemoUi.tokens.textColorButton) {
                        val chip = Host.metaTag(this@ChatActivity, text, accent, HostMetrics.SEX_TAG_H, 8f, textColor)
                        addView(chip, LinearLayout.LayoutParams(-2, DemoUi.dp(this@ChatActivity, HostMetrics.SEX_TAG_H)).apply {
                            if (childCount > 0) marginStart = DemoUi.dp(this@ChatActivity, 4)
                        })
                    }
                    val p = profile
                    if (p != null) {
                        p.city.takeIf { it.isNotBlank() }?.let { addChip(it, Host.tagAccent(TagKind.CITY)) }
                        if (p.age > 0) addChip(DemoText.get(BaseR.string.demo_age_years, p.age.toString()), Host.tagAccent(Host.ageKind(p.sex)))
                        if (p.height > 0) addChip(DemoText.get(BaseR.string.demo_height_cm, p.height.toString()), Host.tagAccent(TagKind.HEIGHT))
                    }
                    if (childCount == 0) {
                        addChip(DemoText.get(R.string.demo_unknown), DemoUi.tokens.bgColorFunction, DemoUi.tokens.textColorSecondary)
                    }
                }
                subtitleView = plain
                addView(plain, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
            })
            if (!preview && peerFixtureId != null) {
                contentDescription = DemoText.get(R.string.demo_view_profile)
                setOnClickListener { openPeerProfile() }
            }
        }, FrameLayout.LayoutParams(-2, -1, Gravity.CENTER).apply {
            marginStart = DemoUi.dp(this@ChatActivity, 96)
            marginEnd = DemoUi.dp(this@ChatActivity, 96)
        })
        addView(LinearLayout(this@ChatActivity).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(DemoGlyph(this@ChatActivity, DemoGlyph.Type.MORE).apply {
                contentDescription = DemoText.get(BaseR.string.demo_more)
                setOnClickListener { openChatSettings() }
            }, LinearLayout.LayoutParams(DemoUi.dp(this@ChatActivity, 40), DemoUi.dp(this@ChatActivity, 52)))
        }, FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.CENTER_VERTICAL).apply {
            marginEnd = DemoUi.dp(this@ChatActivity, 4)
        })
    }

    /**
     * Ice-breaker card: the first item of the chat (docs/05 §14.166, design board M). Mock data from the peer's fixture
     * profile only; no IM data. Hidden when the peer has no fixture or the profile is too thin to show.
     */
    private fun installIcebreaker(chat: ChatPageView) {
        val fixtureId = peerFixtureId ?: return
        val show = { detail: HomeUserDetail ->
            if (!isFinishing && !isDestroyed && IcebreakerCard.hasContent(detail)) {
                chat.setMessageListHeader(
                    IcebreakerCard.build(this, detail, IcebreakerCard.Actions(
                        onProfile = { openPeerProfile() },
                        onAlbum = { openPeerAlbum() }
                    )),
                    heightFraction = 1f / 3f,
                    minHeightDp = ICEBREAKER_MIN_HEIGHT_DP
                )
            }
        }
        HomeKit.cachedDetail(fixtureId)?.let { return show(it) }
        HomeKit.dataSource.loadUserDetail(fixtureId) { result ->
            result.getOrNull()?.let {
                HomeKit.cacheDetail(fixtureId, it)
                show(it)
            }
        }
    }

    private fun openPeerAlbum() {
        val fixtureId = peerFixtureId ?: return
        startActivity(Intent(this, io.trtc.tuikit.chat.home.AlbumActivity::class.java)
            .putExtra(io.trtc.tuikit.chat.home.ProfileActivity.EXTRA_USER_KEY, fixtureId))
    }

    private fun openPeerProfile() {
        val fixtureId = peerFixtureId ?: return
        startActivity(Intent(this, io.trtc.tuikit.chat.home.ProfileActivity::class.java)
            .putExtra(io.trtc.tuikit.chat.home.ProfileActivity.EXTRA_USER_KEY, fixtureId)
            .putExtra(io.trtc.tuikit.chat.home.ProfileActivity.EXTRA_FROM_CHAT, true))
    }

    private fun previewBanner() = DemoUi.text(this, DemoText.get(R.string.demo_ui_preview_not_logged_in_no_message), 11f, DemoUi.MUTED).apply {
        setBackgroundColor(Color.parseColor(DemoUi.SURFACE_HIGH))
        setPadding(DemoUi.dp(this@ChatActivity, 16), DemoUi.dp(this@ChatActivity, 7),
            DemoUi.dp(this@ChatActivity, 16), DemoUi.dp(this@ChatActivity, 7))
    }

    /** Screen-level mock safety tip; it is not an IM message and never fakes a recall. */
    private fun safetyBanner(text: String): View {
        val warningInk = DemoUi.hex(DemoUi.tokens.textColorWarning)
        val banner = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(DemoUi.tokens.toastColorWarning)
            setPadding(DemoUi.dp(this@ChatActivity, 14), DemoUi.dp(this@ChatActivity, 3),
                DemoUi.dp(this@ChatActivity, 6), DemoUi.dp(this@ChatActivity, 3))
        }
        banner.addView(DemoGlyph(this, DemoGlyph.Type.WARNING, warningInk),
            LinearLayout.LayoutParams(DemoUi.dp(this, 18), DemoUi.dp(this, 18)))
        banner.addView(DemoUi.text(this, text, 12f, warningInk).apply {
            setPadding(DemoUi.dp(this@ChatActivity, 6), 0, 0, 0)
            maxLines = 1
        }, LinearLayout.LayoutParams(0, -2, 1f))
        banner.addView(DemoGlyph(this, DemoGlyph.Type.CLOSE, warningInk).apply {
            contentDescription = DemoText.get(R.string.demo_dismiss)
            setOnClickListener {
                DemoChatSession.dismissBanner(conversationId)
                banner.visibility = View.GONE
            }
        }, LinearLayout.LayoutParams(DemoUi.dp(this, 32), DemoUi.dp(this, 28)))
        return banner
    }

    /** Design S3 `527:1626`: 30dp pills, 14dp colour icon + 12sp label, 5dp gap, 11dp / 13dp side padding. */
    private fun chipRow(chips: List<DemoQuickChip>) = HorizontalScrollView(this).apply {
        isHorizontalScrollBarEnabled = false
        addView(LinearLayout(this@ChatActivity).apply {
            // The UIKit footer overlay already sits 12dp from the screen edge (iOS: 16pt in total), so only 4dp here.
            // Vertically the overlay is flush with the input bar and these 4dp are the whole gap, which is the 4pt
            // the iOS chip row keeps above its input bar.
            setPadding(DemoUi.dp(this@ChatActivity, 4), DemoUi.dp(this@ChatActivity, 2),
                DemoUi.dp(this@ChatActivity, 16), DemoUi.dp(this@ChatActivity, 4))
            chips.forEach { chip ->
                addView(LinearLayout(this@ChatActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    contentDescription = chip.label
                    setPaddingRelative(DemoUi.dp(this@ChatActivity, 11), 0, DemoUi.dp(this@ChatActivity, 13), 0)
                    background = DemoUi.rounded(DemoUi.SURFACE_HIGH, 17, this@ChatActivity, DemoUi.hex(DemoUi.tokens.strokeColorPrimary))
                    CHIP_DRAWABLES[chip.icon]?.let { icon ->
                        addView(ImageView(this@ChatActivity).apply { setImageResource(icon) },
                            LinearLayout.LayoutParams(DemoUi.dp(this@ChatActivity, 16), DemoUi.dp(this@ChatActivity, 16)).apply {
                                marginEnd = DemoUi.dp(this@ChatActivity, 5)
                            })
                    }
                    addView(DemoUi.text(this@ChatActivity, chip.label, 14f, DemoUi.TEXT))
                    setOnClickListener {
                        sendDemoCard(chip.id, chip.kind, chip.summary, DemoCardRolls.rolled(chip.kind, chip.payload))
                    }
                }, LinearLayout.LayoutParams(-2, DemoUi.dp(this@ChatActivity, 34)).apply { marginEnd = DemoUi.dp(this@ChatActivity, 8) })
            }
        })
    }

    /** A received card invited another round; the answer is a fresh card of the same kind with its own roll. */
    private fun replayCard(kind: String) {
        if (kind != "rps") return
        sendDemoCard(kind, kind, DemoCardProtocol.summaryOf(kind), DemoCardRolls.rolled(kind, emptyMap()))
    }

    /**
     * Sends a real IM CUSTOM message whose content is local demo data. [key] identifies the
     * entry point (chip or tile) so a failed send is retried as the same interaction.
     */
    private fun sendDemoCard(
        key: String, kind: String, summary: String, payload: Map<String, Any>,
        onResult: ((instanceId: String?) -> Unit)? = null
    ) {
        if (preview) {
            toast(DemoText.get(R.string.demo_preview_mode_not_logged_in_interaction_card), SocialToast.Kind.WARNING)
            onResult?.invoke(null)
            return
        }
        if (!sending.add(key)) {
            onResult?.invoke(null)
            return
        }
        val (instanceId, eventId) = pendingCards[key]
            ?: (UUID.randomUUID().toString() to UUID.randomUUID().toString())
        val data = runCatching {
            DemoCardProtocol.build(kind, payload, instanceId = instanceId, eventId = eventId)
        }.getOrElse {
            sending.remove(key)
            toast(DemoText.get(R.string.demo_this_interaction_card_format_is_not_supported), SocialToast.Kind.WARNING)
            onResult?.invoke(null)
            return
        }
        cardSender.sendMessage(
            SendMessagePayload.CustomSendMessagePayload(data, summary, null),
            null,
            object : CompletionHandler {
                override fun onSuccess() = runOnUiThread {
                    sending.remove(key)
                    pendingCards.remove(key)
                    onReplySent()
                    onResult?.invoke(instanceId)
                }

                override fun onFailure(code: Int, desc: String) = runOnUiThread {
                    sending.remove(key)
                    pendingCards[key] = instanceId to eventId
                    HostDiagnostics.record("chat.sendCard", code, desc)
                    toast(DemoText.get(R.string.demo_send_failed_tap_again_to_retry_the), SocialToast.Kind.ERROR)
                    onResult?.invoke(null)
                }
            }
        )
    }

    private fun peerUserId(): String? =
        conversationId.takeIf { it.startsWith("c2c_") }?.removePrefix("c2c_")?.takeIf { it.isNotBlank() }

    private fun startCall(mediaType: CallMediaType) {
        val peer = peerUserId() ?: return
        when {
            preview -> toast(DemoText.get(R.string.demo_preview_mode_not_logged_in_cannot_start), SocialToast.Kind.WARNING)
            !callReady -> {
                HostDiagnostics.record("chat.call", 0, "call component not ready")
                toast(DemoText.get(R.string.demo_the_call_component_is_not_ready_log), SocialToast.Kind.WARNING)
            }
            else -> AtomicCallEventPublisher.publishStartCall(
                listOf(peer),
                if (mediaType == CallMediaType.Video) AtomicCallEventPublisher.MEDIA_TYPE_VIDEO
                else AtomicCallEventPublisher.MEDIA_TYPE_AUDIO
            )
        }
    }

    private fun onReplySent() {
        if (!preview) DemoGroupWatcher.noteReplied(conversationId)
    }

    private fun setPeerTyping(typing: Boolean) {
        val titleText = titleView ?: return
        val plain = subtitleView ?: return
        val showing = titleText.text.toString() != headerTitle
        if (typing == showing) return
        titleText.animate().cancel()
        plain.animate().cancel()
        titleText.text = if (typing) DemoText.get(R.string.demo_typing_now) else headerTitle
        titleText.setTextColor(if (typing) DemoUi.tokens.textColorLink else DemoUi.tokens.textColorPrimary)
        titleText.alpha = 0f
        titleText.animate().alpha(1f).setDuration(TYPING_FADE_MS).start()
        plain.animate().alpha(if (typing) 0f else 1f).setDuration(TYPING_FADE_MS).start()
    }

    override fun onResume() {
        super.onResume()
        if (!preview) DemoSession.activeConversationId = conversationId
    }

    override fun onPause() {
        if (DemoSession.activeConversationId == conversationId) DemoSession.activeConversationId = ""
        super.onPause()
    }

    private fun toast(
        message: String,
        kind: SocialToast.Kind = SocialToast.Kind.DEFAULT,
        duration: SocialToast.Duration = SocialToast.Duration.SHORT
    ) = SocialToast.show(this, message, kind, duration)

    companion object {
        private const val TYPING_FADE_MS = 160L

        /** Ice-breaker card is one third of the chat page, but never shorter than 280dp (the tallest content: two-line common box + voice pill). */
        private const val ICEBREAKER_MIN_HEIGHT_DP = 280

        /** Tile bitmaps exported by tools/export_more_panel_tiles.py (explicit for R8). */
        private val TILE_DRAWABLES = mapOf(
            "demo_fn_location" to R.drawable.demo_fn_location,
            "demo_fn_burn" to R.drawable.demo_fn_burn,
            "demo_fn_listen" to R.drawable.demo_fn_listen,
            "demo_fn_game" to R.drawable.demo_fn_game,
            "demo_fn_watch" to R.drawable.demo_fn_watch,
            "demo_fn_redpacket" to R.drawable.demo_fn_redpacket,
            "demo_fn_album" to R.drawable.demo_fn_album,
            "demo_fn_quiz" to R.drawable.demo_fn_quiz
        )

        private val CHIP_DRAWABLES = mapOf(
            "demo_chip_pat" to R.drawable.demo_chip_pat,
            "demo_chip_listen" to R.drawable.demo_chip_listen,
            "demo_chip_swap" to R.drawable.demo_chip_swap,
            "demo_chip_rps" to R.drawable.demo_chip_rps
        )

        private val QUICK_DRAWABLES = mapOf(
            "demo_qa_image" to R.drawable.demo_qa_image,
            "demo_qa_call" to R.drawable.demo_qa_call,
            "demo_qa_gift" to R.drawable.demo_qa_gift,
            "demo_qa_emoji" to R.drawable.demo_qa_emoji,
            "demo_qa_more" to R.drawable.demo_qa_more,
            "demo_qa_more_on" to R.drawable.demo_qa_more_on
        )
    }
}
