package io.trtc.tuikit.chat.demo.main

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.tencent.imsdk.v2.V2TIMManager
import com.tencent.imsdk.v2.V2TIMUserFullInfo
import com.tencent.imsdk.v2.V2TIMValueCallback
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.call.CallDirection
import io.trtc.tuikit.atomicxcore.api.call.CallInfo
import io.trtc.tuikit.atomicxcore.api.call.CallMediaType
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationGroup
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationListStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationLoadOption
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.social.ConversationSlot
import io.trtc.tuikit.chat.demo.social.DemoBadgeCenter
import io.trtc.tuikit.chat.demo.social.DemoBadgeRules
import io.trtc.tuikit.chat.demo.social.DemoConversationClassifier
import io.trtc.tuikit.chat.demo.social.DemoGroupDiagnostics
import io.trtc.tuikit.chat.demo.social.DemoPeerTags
import io.trtc.tuikit.chat.demo.social.DemoGroupWatcher
import io.trtc.tuikit.chat.demo.social.DemoUserProfileCache
import io.trtc.tuikit.chat.demo.social.badgeCandidates
import io.trtc.tuikit.chat.hostbase.AvatarView
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostHeader
import io.trtc.tuikit.chat.hostbase.HostImage
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.HostSegBar
import io.trtc.tuikit.chat.hostbase.HostSwipePager
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.uikit.components.common.ChatDateTimeUtils
import io.trtc.tuikit.chat.uikit.components.contactlist.config.ChatContactListConfig
import io.trtc.tuikit.chat.uikit.components.conversationlist.config.ConversationMatcher
import io.trtc.tuikit.chat.uikit.components.conversationlist.utils.ConversationUnreadClearer
import io.trtc.tuikit.chat.uikit.components.conversationlist.utils.isUnread
import io.trtc.tuikit.chat.uikit.components.emojipicker.EmojiSpanHelper
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.MessageListMessageSummaryFormatter
import io.trtc.tuikit.chat.uikit.pages.ContactsPageView
import io.trtc.tuikit.chat.uikit.pages.ConversationsPageView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import kotlin.math.min

/**
 * Messages tab (design S1 `527:167`, S2 `527:636`, 好友 S5, 通话记录):
 * header 「消息」 (add friend; the light/dark choice lives in 我的 → 设置) and segment tabs 消息 / 好友 / 通话.
 *
 *  - 消息: search bar, the 「打招呼消息」 entry row (72dp, count badge, chevron; opens the
 *    greeting second-level page listing the real conversations that carry the greeting mark), group
 *    line, group header 「最近聊天」 and the real one-to-one conversations without it.
 *  - 好友: the real friend list (A-Z), only the real 「新的联系人」 entry is kept.
 *  - 通话: the SDK's real recent call records (CallStore); tapping a row calls back.
 * No local array stands in for IM data.
 */
class GroupedMessagesView(
    context: Context,
    private val callReady: Boolean = true,
    private val preview: Boolean = false,
    private val onConversationClick: (ConversationInfo) -> Unit,
    private val onContactClick: (String) -> Unit = {},
    private val onSearchClick: () -> Unit = {},
    private val onCallBack: (peerId: String, video: Boolean) -> Unit = { _, _ -> }
) : LinearLayout(context) {
    companion object {
        const val SEG_MESSAGES = 0
        const val SEG_CONTACTS = 1
        const val SEG_CALLS = 2
    }

    private val tokens get() = DemoUi.tokens
    private val holder = FrameLayout(context)

    /** The three segment pages: each is built the first time it is shown and then only slid in / out. */
    private val pager = HostSwipePager(context)
    private var greetingOverlay: View? = null
    private val segBar: HostSegBar
    private var selected = SEG_MESSAGES
    private var greetingPage: View? = null
    private var scope: CoroutineScope? = null
    private var greetingJob: Job? = null
    private var entryDesc: TextView? = null
    private var entryBadgeHolder: FrameLayout? = null
    private var greetingDescText = DemoText.get(R.string.demo_no_new_greetings)
    private var greetingUnread = 0
    private var recentList: ConversationsPageView? = null
    private var greetingList: ConversationsPageView? = null

    init {
        orientation = VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        segBar = HostSegBar(context, listOf(DemoText.get(R.string.demo_messages), DemoText.get(R.string.demo_friends), DemoText.get(R.string.demo_calls)), selected) { index ->
            selected = index
            greetingPage = null
            render(animate = true)
        }
        addView(segBar)
        addView(holder, LayoutParams(-1, 0, 1f))
        pager.pageCount = SEG_CALLS + 1
        pager.provider = { position -> pageFor(position) }
        // The tab bar travels with the pages (tap slide, drag and settle), see HostSegBar.setPosition.
        pager.onProgress = { position -> segBar.setPosition(position) }
        pager.onSwiped = { position ->
            selected = position
            pageShown(position)
        }
        if (!preview) holder.addView(pager, FrameLayout.LayoutParams(-1, -1))
        render()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        observeGreetings()
        if (!preview) {
            scope?.launch { DemoBadgeCenter.messagesSegment.collect { segBar.setBadge(SEG_MESSAGES, it) } }
            scope?.launch { DemoBadgeCenter.friendsSegment.collect { segBar.setBadge(SEG_CONTACTS, it) } }
            scope?.launch {
                DemoGroupWatcher.state.map { it.context }.distinctUntilChanged().drop(1).collect {
                    recentList?.refreshExclusion()
                    greetingList?.refreshExclusion()
                }
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        scope?.cancel()
        scope = null
    }

    /** Switch segment from outside (debug deep link); 0 = 消息, 1 = 好友, 2 = 通话. */
    fun selectSegment(index: Int) {
        if (index !in SEG_MESSAGES..SEG_CALLS) return
        selected = index
        greetingPage = null
        render()
    }

    private fun pageFor(position: Int): View = when (position) {
        SEG_CONTACTS -> contactsPage()
        SEG_CALLS -> CallRecordsView(context, callReady, onCallBack).also { callsPage = it }
        else -> messagesPage()
    }

    private var callsPage: CallRecordsView? = null

    /** Called whenever a segment becomes the visible one (tap, swipe or deep link). */
    private fun pageShown(position: Int) {
        // Call records can change while another screen was on top; the view dedupes, so an unchanged list is not redrawn.
        if (position == SEG_CALLS) callsPage?.refresh()
    }


    /** Back from the greeting second-level page; returns true when it consumed the event. */
    fun handleBack(): Boolean {
        if (greetingPage == null) return false
        greetingPage = null
        render()
        return true
    }

    /** Group capability changed (e.g. the package turned out not to support groups): rebuild pages and entry. */
    fun onGroupStateChanged() {
        recentList = null
        entryDesc = null
        entryBadgeHolder = null
        pager.invalidate(SEG_MESSAGES)
        if (greetingPage != null) openGreetings() else render()
        observeGreetings()
    }

    // ------------------------------------------------------------------ segments

    private fun render(animate: Boolean = false) {
        // A tap is answered by the pager's slide, which moves the bar frame by frame; only a jump snaps it here.
        if (!animate || preview || greetingPage != null) segBar.select(selected, notify = false)
        // The greeting second-level page brings its own header and covers the whole tab.
        val secondLevel = greetingPage != null
        segBar.visibility = if (secondLevel) GONE else VISIBLE
        greetingOverlay?.let { holder.removeView(it) }
        greetingOverlay = null
        if (greetingPage == null) greetingList = null
        if (preview) {
            if (holder.childCount == 0) holder.addView(previewNotice())
            return
        }
        greetingPage?.let {
            it.isClickable = true
            holder.addView(it, FrameLayout.LayoutParams(-1, -1))
            greetingOverlay = it
            return
        }
        pager.show(selected, animate)
        if (animate) pageShown(selected)
    }

    private fun previewNotice() = Host.text(context, DemoText.get(R.string.demo_preview_mode_im_is_not_logged_in), 13f, tokens.textColorTertiary).apply {
        gravity = Gravity.CENTER
        setPadding(Host.dp(context, 24), 0, Host.dp(context, 24), 0)
    }.let { text -> FrameLayout(context).apply { addView(text, FrameLayout.LayoutParams(-1, -1)) } }

    private fun messagesPage() = ConversationsPageView(context).apply {
        setup(
            showSearchBar = true,
            searchHint = DemoText.get(R.string.demo_search_nickname_user_id),
            showHeader = false,
            conversationGroup = ConversationGroup.C2C.value,
            conversationExclusion = ConversationMatcher { DemoGroupWatcher.slotOf(it) != ConversationSlot.RECENT },
            emptyHint = DemoGroupDiagnostics.emptyHint(DemoText.get(R.string.demo_no_recent_messages_yet)),
            topContent = entryBlock(),
            onSearchClick = { if (!preview) onSearchClick() },
            onConversationClick = { conversation -> onConversationClick(conversation) },
            // 消息 tab: long-press menus only, so a horizontal drag pages to 好友 / 通话 (see docs/05 §14.99).
            swipeToReveal = false,
            titleAccessory = { conversation -> peerTags(conversation.conversationID) }
        )
        recentList = this
    }

    private fun peerTags(conversationID: String): View? =
        DemoPeerTags.inline(context, conversationID.removePrefix("c2c_"))

    private fun contactsPage() = ContactsPageView(context).apply {
        setup(
            config = ChatContactListConfig(
                showNewContacts = true,
                showGroupApplications = false,
                showMyGroups = false,
                showBlacklist = true,
                showSearchBar = true,
            ),
            showHeader = false,
            onContactClick = { contact -> onContactClick(contact.userID) },
            subtitleAccessory = { userID -> DemoPeerTags.inline(context, userID) },
            peerTags = { userID -> DemoPeerTags.inline(context, userID) },
            peerFullTags = { userID -> DemoPeerTags.full(context, userID) }
        )
    }

    // ------------------------------------------------------------------ 打招呼消息

    /** Entry row + 1px group line + 「最近聊天」 header, all on the list surface (bgColorTopBar). */
    private fun entryBlock(): View = LinearLayout(context).apply {
        orientation = VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        addView(entryRow())
        addView(View(context).apply { setBackgroundColor(tokens.strokeColorPrimary) },
            LayoutParams(-1, Host.dp(context, 1).coerceAtLeast(1)))
        addView(Host.text(context, DemoText.get(R.string.demo_recent_chats), 13f, tokens.textColorTertiary, bold = true).apply {
            setPadding(Host.dp(context, HostMetrics.SCREEN_PADDING_H), Host.dp(context, 12),
                Host.dp(context, HostMetrics.SCREEN_PADDING_H), Host.dp(context, 6))
        })
    }

    /** `.entryrow`: 72dp, 48dp gradient circle with a white heart, title 18, desc 14, badge + chevron. */
    private fun entryRow(): View {
        val c = tokens
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        val desc = Host.text(
            context,
            EmojiSpanHelper.replaceEmojiKeysWithNames(greetingDescText),
            14f,
            c.textColorSecondary,
            single = true
        )
        entryDesc = desc
        val badgeHolder = FrameLayout(context)
        entryBadgeHolder = badgeHolder
        applyGreetingEntry()
        return LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(pad, 0, pad, 0)
            minimumHeight = Host.dp(context, HostMetrics.CONV_ITEM_H)
            layoutParams = LayoutParams(-1, Host.dp(context, HostMetrics.CONV_ITEM_H))
            contentDescription = DemoText.get(R.string.demo_greetings)
            addView(FrameLayout(context).apply {
                background = Host.brandGradient(context, 24f, oval = true).apply {
                    orientation = GradientDrawable.Orientation.TL_BR
                }
                addView(GreetingGlyph(context, c.buttonColorPrimaryDefault),
                    FrameLayout.LayoutParams(-1, -1))
            }, LayoutParams(Host.dp(context, HostMetrics.CONV_AVATAR), Host.dp(context, HostMetrics.CONV_AVATAR)).apply {
                marginEnd = Host.dp(context, 12)
            })
            addView(LinearLayout(context).apply {
                orientation = VERTICAL
                addView(Host.text(context, DemoText.get(R.string.demo_greetings), 18f, c.textColorPrimary, single = true))
                addView(desc, LayoutParams(-1, -2).apply { topMargin = Host.dp(context, 2) })
            }, LayoutParams(0, -2, 1f))
            addView(badgeHolder, LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 8) })
            addView(Host.icon(context, BaseR.drawable.demo_ic_chevron, 12, c.textColorTertiary),
                LayoutParams(Host.dp(context, 12), Host.dp(context, 12)).apply { marginStart = Host.dp(context, 8) })
            setOnClickListener { openGreetings() }
        }
    }

    private fun observeGreetings() {
        if (preview) return
        greetingJob?.cancel()
        val formatter = MessageListMessageSummaryFormatter()
        greetingJob = scope?.launch {
            DemoGroupWatcher.state.collectLatest { view ->
                val members = DemoGroupWatcher.greetingMembers(view)
                val latest = members.maxByOrNull { it.lastMessage?.timestamp ?: 0L }
                val preview = latest?.lastMessage?.let { formatter.format(context, it, latest.conversationID) }
                greetingUnread = DemoBadgeRules.greetingUnread(view.badgeCandidates())
                greetingDescText = when {
                    latest == null && DemoGroupDiagnostics.packageUnsupported -> DemoText.get(R.string.demo_conversation_groups_are_unavailable_the_ultimate)
                    latest == null -> DemoText.get(R.string.demo_no_new_greetings)
                    preview.isNullOrBlank() -> latest.title.orEmpty()
                    else -> "${latest.title.orEmpty()}：$preview"
                }
                applyGreetingEntry()
            }
        }
    }

    private fun applyGreetingEntry() {
        // 打招呼摘要里的表情在 IM 里是「[TUIEmoji_Smile]」这种 key，直接 setText 会露出 key。
        // 与最近聊天 / 会话列表同一套做法：先显示表情名兜底，再把 key 画成表情图。
        val raw = greetingDescText
        entryDesc?.let { view ->
            view.text = EmojiSpanHelper.replaceEmojiKeysWithNames(raw)
            EmojiSpanHelper.applyEmojiSpans(context, raw, view.textSize, null) { spanned ->
                if (greetingDescText == raw) view.text = spanned
            }
        }
        entryBadgeHolder?.let { holderView ->
            holderView.removeAllViews()
            if (greetingUnread > 0) holderView.addView(Host.badge(context, greetingUnread))
        }
    }

    private fun openGreetings() {
        val c = tokens
        val page = LinearLayout(context).apply {
            orientation = VERTICAL
            setBackgroundColor(c.bgColorTopBar)
        }
        val back = Host.backButton(context) { handleBack() }
        val readAll = Host.text(context, DemoText.get(R.string.demo_ignore_unread), 14f, c.textColorLink).apply {
            contentDescription = DemoText.get(R.string.demo_ignore_unread)
            setOnClickListener { confirmIgnoreGreetingUnread() }
        }
        page.addView(HostHeader(context, DemoText.get(R.string.demo_greetings), left = back, ops = listOf(readAll)).also {
            it.addView(View(context).apply { setBackgroundColor(c.strokeColorSecondary) },
                FrameLayout.LayoutParams(-1, Host.dp(context, 1).coerceAtLeast(1), Gravity.BOTTOM))
        })
        page.addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(c.bgColorOperate)
            setPadding(Host.dp(context, HostMetrics.SCREEN_PADDING_H), Host.dp(context, 8), Host.dp(context, HostMetrics.SCREEN_PADDING_H), Host.dp(context, 8))
            addView(Host.icon(context, R.drawable.demo_ic_heart, 14, c.tagColorLevel4),
                LayoutParams(Host.dp(context, 14), Host.dp(context, 14)).apply { marginEnd = Host.dp(context, 6) })
            addView(Host.text(context, DemoText.get(R.string.demo_messages_and_calls_from_strangers_land_here), 12f, c.textColorSecondary), LayoutParams(0, -2, 1f))
        })
        val list = ConversationsPageView(context).apply {
            setup(
                showSearchBar = false,
                showHeader = false,
                conversationExclusion = ConversationMatcher { DemoGroupWatcher.slotOf(it) != ConversationSlot.GREETING },
                emptyHint = DemoGroupDiagnostics.emptyHint(DemoText.get(R.string.demo_no_new_greeting_messages)),
                onConversationClick = { conversation -> onConversationClick(conversation) },
                loadOption = ConversationLoadOption(markType = DemoConversationClassifier.GREETING_MARK),
                swipeToReveal = false,
                titleAccessory = { conversation -> peerTags(conversation.conversationID) }
            )
        }
        page.addView(list, LayoutParams(-1, 0, 1f))
        greetingList = list
        greetingPage = page
        render()
    }

    /** 有未读数，或被标为未读（只有标记、没有未读数）的打招呼会话，都算“未读”。 */
    private fun greetingUnreadTargets(): List<ConversationInfo> =
        DemoGroupWatcher.greetingMembers().filter { it.isUnread }

    /** 忽略未读会一次清掉全部打招呼会话的未读，先二次确认；没有可忽略的未读时不弹框。 */
    private fun confirmIgnoreGreetingUnread() {
        if (greetingUnreadTargets().isEmpty()) return
        Host.showThemed(context, android.app.AlertDialog.Builder(context)
            .setTitle(DemoText.get(R.string.demo_ignore_unread))
            .setMessage(DemoText.get(R.string.demo_ignore_unread_confirm_message))
            .setNegativeButton(DemoText.get(BaseR.string.demo_cancel), null)
            .setPositiveButton(DemoText.get(R.string.demo_confirm)) { _, _ -> ignoreGreetingUnread() })
    }

    private fun ignoreGreetingUnread() {
        // 确认弹框期间会话可能已变化，按点“确定”时的最新状态再取一遍。
        ConversationUnreadClearer.clearConversationsUnread(ConversationListStore.create(), greetingUnreadTargets())
    }
}

/**
 * Call records (design 通话 `.call`): 72dp rows with a 48dp avatar, name 18, direction + duration 14
 * (missed in the error colour), time 12 and a primary-coloured call icon. Data comes from the SDK
 * (`CallStore.queryRecentCalls`); names and avatars from the real IM profiles of the peers.
 */
class CallRecordsView(
    context: Context,
    private val callReady: Boolean,
    private val onCallBack: (peerId: String, video: Boolean) -> Unit
) : LinearLayout(context) {
    private val tokens get() = DemoUi.tokens
    /** Built rows by call id: a row is rebuilt only when what it shows changed, so avatars are not reloaded. */
    private val rowCache = HashMap<String, Pair<String, View>>()

    private val list = LinearLayout(context).apply { orientation = VERTICAL }
    private val self: String = V2TIMManager.getInstance().loginUser.orEmpty()
    private val profiles = HashMap<String, V2TIMUserFullInfo>()
    private var records: List<CallInfo> = emptyList()
    private var scope: CoroutineScope? = null
    private var query = ""
    private val input = android.widget.EditText(context)
    private val clear = Host.text(context, "✕", 14f, tokens.textColorTertiary).apply { gravity = Gravity.CENTER }

    /** True once the first complete list (nicknames + pictures) is on screen. */
    private var ready = false
    private val loading = FrameLayout(context).apply {
        visibility = GONE
        isClickable = true
        addView(android.widget.ProgressBar(context).apply {
            indeterminateTintList = android.content.res.ColorStateList.valueOf(tokens.buttonColorPrimaryDefault)
        }, FrameLayout.LayoutParams(Host.dp(context, 30), Host.dp(context, 30), Gravity.CENTER))
    }

    init {
        orientation = VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        addView(searchBar())
        addView(FrameLayout(context).apply {
            addView(ScrollView(context).apply {
                isVerticalScrollBarEnabled = false
                addView(list)
            }, FrameLayout.LayoutParams(-1, -1))
            addView(loading, FrameLayout.LayoutParams(-1, -1))
        }, LayoutParams(-1, 0, 1f))
        // Loading from the start: the store's first emission is often an empty list, which must not flash the
        // "no records yet" text before the real ones arrive.
        loading.visibility = VISIBLE
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        CallStore.shared.queryRecentCalls("", 0, object : CompletionHandler {
            override fun onSuccess() = Unit
            override fun onFailure(code: Int, desc: String) = Unit
        })
        // Nothing came back (offline / empty account): show the empty state instead of spinning forever.
        postDelayed({
            if (!ready && records.isEmpty()) {
                loading.visibility = GONE
                render()
            }
        }, EMPTY_WAIT_MS)
        scope?.launch {
            CallStore.shared.observerState.recentCalls.collectLatest { set ->
                records = set.sortedByDescending { it.startTime }
                prepare()
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        scope?.cancel()
        scope = null
    }

    private fun searchBar(): View {
        val c = tokens
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        return FrameLayout(context).apply {
            setBackgroundColor(c.bgColorTopBar)
            setPadding(pad, Host.dp(context, 4), pad, Host.dp(context, 12))
            addView(LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = Host.rounded(context, c.bgColorInput, HostMetrics.SEARCH_BAR_RADIUS.toFloat())
                setPadding(Host.dp(context, 12), 0, Host.dp(context, 12), 0)
                addView(Host.icon(context, BaseR.drawable.demo_hd_search, 16, c.textColorSecondary))
                input.apply {
                    hint = DemoText.get(R.string.demo_search_call_records)
                    setHintTextColor(c.textColorTertiary)
                    setTextColor(c.textColorPrimary)
                    textSize = 14f
                    background = null
                    setPadding(0, 0, 0, 0)
                    isSingleLine = true
                    includeFontPadding = false
                    imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
                    inputType = android.text.InputType.TYPE_CLASS_TEXT
                    addTextChangedListener(object : android.text.TextWatcher {
                        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                            query = s?.toString().orEmpty().trim()
                            clear.visibility = if (query.isEmpty()) GONE else VISIBLE
                            render()
                        }
                        override fun afterTextChanged(s: android.text.Editable?) = Unit
                    })
                    setOnEditorActionListener { view, _, _ ->
                        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager)
                            .hideSoftInputFromWindow(view.windowToken, 0)
                        true
                    }
                }
                addView(input, LayoutParams(0, -2, 1f).apply { marginStart = Host.dp(context, 6) })
                clear.apply {
                    visibility = GONE
                    contentDescription = DemoText.get(R.string.demo_clear_input)
                    setOnClickListener { input.setText("") }
                }
                addView(clear, LayoutParams(Host.dp(context, 24), Host.dp(context, 24)).apply { marginStart = Host.dp(context, 4) })
            }, FrameLayout.LayoutParams(-1, Host.dp(context, HostMetrics.SEARCH_BAR_H)))
        }
    }

    private fun peerOf(info: CallInfo): String? {
        val peers = (listOf(info.inviterId) + info.inviteeIds).filter { it.isNotBlank() && it != self }
        return peers.firstOrNull()
    }

    /**
     * First paint only happens once every peer has a nickname and the avatars are already in the picture cache: the
     * list used to render with userIDs and letter avatars and then rebuild itself twice, which is what flickered.
     * Later updates render straight away — the row cache keeps everything that did not change.
     */
    private fun prepare() {
        val peers = records.mapNotNull { peerOf(it) }.distinct()
        if (ready) {
            peers.forEach { DemoUserProfileCache.get(it)?.let { info -> profiles[it] = info } }
            render()
            return
        }
        // The first emission of the store is often an empty list: keep the loading state until the timeout above.
        if (records.isEmpty()) return
        loading.visibility = VISIBLE
        DemoUserProfileCache.load(peers) {
            peers.forEach { DemoUserProfileCache.get(it)?.let { info -> profiles[it] = info } }
            prefetchThenShow(peers)
        }
    }

    private fun prefetchThenShow(peers: List<String>) {
        if (ready) {
            render()
            return
        }
        var shown = false
        fun show() {
            if (shown) return
            shown = true
            loading.visibility = GONE
            ready = true
            render()
        }
        val urls = peers.mapNotNull { profiles[it]?.faceUrl }
        if (urls.isEmpty()) {
            show()
            return
        }
        HostImage.prefetch(urls) { post { show() } }
        // A slow picture must not keep the page empty: show the list and let that avatar fill in.
        postDelayed({ show() }, PREFETCH_WAIT_MS)
    }

    /** Re-asks the SDK for the records; the list only redraws when something it shows actually changed. */
    fun refresh() {
        CallStore.shared.queryRecentCalls("", 0, object : CompletionHandler {
            override fun onSuccess() = Unit
            override fun onFailure(code: Int, desc: String) = Unit
        })
    }

    private companion object {
        /** Longest the first paint waits for the avatars; after that the list shows with letter avatars. */
        const val PREFETCH_WAIT_MS = 800L

        /** How long the page waits for the first records before showing the empty state. */
        const val EMPTY_WAIT_MS = 1200L
    }

    private fun rowSignature(info: CallInfo): String {
        val peer = peerOf(info).orEmpty()
        val profile = profiles[peer]
        return listOf(info.callId, info.result, info.duration, info.startTime, info.mediaType, peer,
            profile?.nickName.orEmpty(), profile?.faceUrl.orEmpty()).joinToString("|")
    }

    private fun render() {
        list.removeAllViews()
        val shown = visibleRecords()
        rowCache.keys.retainAll(shown.map { it.callId }.toSet())
        if (shown.isEmpty()) {
            val message = if (records.isEmpty()) R.string.demo_no_call_records_yet else R.string.demo_no_matching_call_records
            list.addView(Host.text(context, DemoText.get(message), 13f, tokens.textColorTertiary).apply {
                gravity = Gravity.CENTER
                setPadding(0, Host.dp(context, 48), 0, Host.dp(context, 48))
            }, LayoutParams(-1, -2))
            return
        }
        shown.forEachIndexed { index, info ->
            val signature = rowSignature(info)
            val cached = rowCache[info.callId]
            val view = if (cached != null && cached.first == signature) cached.second else row(info).also { rowCache[info.callId] = signature to it }
            (view.parent as? ViewGroup)?.removeView(view)
            list.addView(view)
            if (index < shown.size - 1) list.addView(divider())
        }
    }

    /** Records whose peer nickname or user ID contains the query (case-insensitive). */
    private fun visibleRecords(): List<CallInfo> {
        if (query.isEmpty()) return records
        return records.filter { info ->
            val peer = peerOf(info).orEmpty()
            val name = profiles[peer]?.nickName.orEmpty()
            name.contains(query, ignoreCase = true) || peer.contains(query, ignoreCase = true)
        }
    }

    private fun divider() = LinearLayout(context).apply {
        orientation = HORIZONTAL
        addView(View(context), LayoutParams(Host.dp(context, 76), Host.dp(context, 1).coerceAtLeast(1)))
        addView(View(context).apply { setBackgroundColor(tokens.strokeColorPrimary) },
            LayoutParams(0, Host.dp(context, 1).coerceAtLeast(1), 1f))
    }

    private fun row(info: CallInfo): View {
        val c = tokens
        val peer = peerOf(info)
        val profile = peer?.let { profiles[it] }
        val name = profile?.nickName?.takeIf { it.isNotBlank() } ?: peer.orEmpty().ifBlank { DemoText.get(R.string.demo_unknown_user) }
        val missed = info.result == CallDirection.Missed
        val video = info.mediaType == CallMediaType.Video
        val direction = when (info.result) {
            CallDirection.Missed -> DemoText.get(R.string.demo_missed_call)
            CallDirection.Incoming -> DemoText.get(R.string.demo_incoming_call)
            else -> DemoText.get(R.string.demo_outgoing_call)
        }
        val duration = if (info.duration > 0) " · ${info.duration / 60}:${(info.duration % 60).toString().padStart(2, '0')}" else ""
        val glyph = if (video) R.drawable.demo_ic_call_video else R.drawable.demo_ic_call_voice
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        return LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(pad, 0, pad, 0)
            layoutParams = LayoutParams(-1, Host.dp(context, HostMetrics.CONV_ITEM_H))
            addView(AvatarView(context, name, DemoUi.ACCENT, HostMetrics.CONV_AVATAR).also { it.load(profile?.faceUrl) },
                LayoutParams(Host.dp(context, HostMetrics.CONV_AVATAR), Host.dp(context, HostMetrics.CONV_AVATAR)).apply { marginEnd = Host.dp(context, 12) })
            addView(LinearLayout(context).apply {
                orientation = VERTICAL
                addView(LinearLayout(context).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(Host.text(context, name, 18f, c.textColorPrimary, single = true))
                    DemoPeerTags.inline(context, peer ?: "")?.let { tags ->
                        addView(tags, LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 6) })
                    }
                })
                addView(LinearLayout(context).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    val tint = if (missed) c.textColorError else c.textColorSecondary
                    addView(Host.icon(context, glyph, 14, tint))
                    addView(Host.text(context, direction + duration, 14f, tint, single = true),
                        LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 4) })
                }, LayoutParams(-1, -2).apply { topMargin = Host.dp(context, 2) })
            }, LayoutParams(0, -2, 1f))
            addView(LinearLayout(context).apply {
                orientation = VERTICAL
                gravity = Gravity.END
                addView(Host.text(context, ChatDateTimeUtils.formatConversationListTime(info.startTime / 1000), 12f, c.textColorSecondary).apply {
                    maxLines = 1
                    setHorizontallyScrolling(true)
                    gravity = Gravity.END
                }, LayoutParams(-2, -2))
                addView(Host.icon(context, glyph, 20, c.buttonColorPrimaryDefault),
                    LayoutParams(Host.dp(context, 20), Host.dp(context, 20)).apply { topMargin = Host.dp(context, 6) })
            }, LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 8) })
            contentDescription = "$name $direction"
            setOnClickListener {
                if (peer != null && callReady) onCallBack(peer, video)
            }
        }
    }
}

class GreetingGlyph(context: Context, heartColor: Int) : View(context) {
    private val white = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val heartPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = heartColor }
    private val tail = Path().apply {
        moveTo(14f, 30f)
        lineTo(13f, 37f)
        lineTo(21f, 31f)
        close()
    }
    private val heart = Path().apply {
        moveTo(12f, 21.35f)
        lineTo(10.55f, 20.03f)
        cubicTo(5.4f, 15.36f, 2f, 12.28f, 2f, 8.5f)
        cubicTo(2f, 5.42f, 4.42f, 3f, 7.5f, 3f)
        cubicTo(9.24f, 3f, 10.91f, 3.81f, 12f, 5.09f)
        cubicTo(13.09f, 3.81f, 14.76f, 3f, 16.5f, 3f)
        cubicTo(19.58f, 3f, 22f, 5.42f, 22f, 8.5f)
        cubicTo(22f, 12.28f, 18.6f, 15.36f, 13.45f, 20.04f)
        close()
        val k = 0.6f
        transform(Matrix().apply {
            setScale(k, k)
            postTranslate(24f - 12f * k, 22.5f - 12.17f * k)
        })
    }

    override fun onDraw(canvas: Canvas) {
        val scale = min(width, height) / 48f
        canvas.save()
        canvas.scale(scale, scale)
        canvas.drawRoundRect(10f, 13f, 38f, 32f, 9f, 9f, white)
        canvas.drawPath(tail, white)
        canvas.drawPath(heart, heartPaint)
        canvas.restore()
    }
}
