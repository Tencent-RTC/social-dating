package io.trtc.tuikit.chat.uikit.pages
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.coordinatorlayout.widget.CoordinatorLayout
import com.google.android.material.appbar.AppBarLayout
import io.trtc.tuikit.chat.uikit.components.conversationlist.config.ChatConversationActionConfig
import io.trtc.tuikit.chat.uikit.components.conversationlist.config.ConversationActionConfigProtocol
import io.trtc.tuikit.chat.uikit.components.conversationlist.config.ConversationGroupMembership
import io.trtc.tuikit.chat.uikit.components.conversationlist.config.ConversationMatcher
import io.trtc.tuikit.chat.uikit.components.conversationlist.ui.ConversationListView
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationListStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationLoadOption
import io.trtc.tuikit.chat.uikit.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class ConversationsPageView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : LinearLayout(context, attrs, defStyleAttr) {

    private val themeStore = ThemeStore.shared(context)
    private var viewScope: CoroutineScope? = null
    private var membershipStore: ConversationListStore? = null
    private var membershipJob: Job? = null
    private var loadOption: ConversationLoadOption? = null

    private val pageHeader: PageHeaderView
    private val coordinatorLayout: CoordinatorLayout
    private val appBarLayout: AppBarLayout
    private val searchBarWrapper: LinearLayout
    private val searchBarInner: LinearLayout
    private val searchIcon: ImageView
    private val searchText: TextView
    private val conversationListView: ConversationListView
    private val searchBarBgDrawable: GradientDrawable
    private var topContentView: View? = null

    private var onSearchClick: (() -> Unit)? = null

    private val density = resources.displayMetrics.density
    private fun dp(value: Int): Int = (value * density).toInt()

    init {
        orientation = VERTICAL
        layoutDirection = LAYOUT_DIRECTION_LOCALE

        pageHeader = PageHeaderView(context)
        addView(pageHeader, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))

        coordinatorLayout = CoordinatorLayout(context)
        addView(coordinatorLayout, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))

        appBarLayout = AppBarLayout(context).apply {
            fitsSystemWindows = false
            stateListAnimator = null
        }
        coordinatorLayout.addView(
            appBarLayout,
            CoordinatorLayout.LayoutParams(
                CoordinatorLayout.LayoutParams.MATCH_PARENT,
                CoordinatorLayout.LayoutParams.WRAP_CONTENT
            )
        )

        searchBarWrapper = LinearLayout(context).apply {
            orientation = HORIZONTAL
            setPadding(dp(16), dp(4), dp(16), dp(12))
        }
        val searchBarParams = AppBarLayout.LayoutParams(
            AppBarLayout.LayoutParams.MATCH_PARENT,
            AppBarLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            // Search bar, entry rows and group header scroll away together with the list and come back only when the
            // list is back at its top (spec 02 S1). No enterAlways / snap: they pulled in half of the entry block.
            scrollFlags = AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL
        }
        appBarLayout.addView(searchBarWrapper, searchBarParams)

        searchBarBgDrawable = GradientDrawable().apply {
            cornerRadius = dp(10).toFloat()
        }

        searchBarInner = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER
            layoutDirection = LAYOUT_DIRECTION_LOCALE
            background = searchBarBgDrawable
            setOnClickListener { onSearchClick?.invoke() }
        }
        searchBarWrapper.addView(
            searchBarInner,
            LayoutParams(LayoutParams.MATCH_PARENT, dp(36))
        )

        searchIcon = ImageView(context).apply {
            setImageResource(R.drawable.uikit_ic_search)
        }
        searchBarInner.addView(searchIcon, LayoutParams(dp(16), dp(16)))

        searchText = TextView(context).apply {
            text = context.getString(R.string.uikit_search_hint)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            val lp = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
            lp.marginStart = dp(6)
            layoutParams = lp
        }
        searchBarInner.addView(searchText)

        conversationListView = ConversationListView(context)
        val listParams = CoordinatorLayout.LayoutParams(
            CoordinatorLayout.LayoutParams.MATCH_PARENT,
            CoordinatorLayout.LayoutParams.MATCH_PARENT
        ).apply {
            behavior = AppBarLayout.ScrollingViewBehavior()
        }
        coordinatorLayout.addView(conversationListView, listParams)

        conversationListView.setup()
        applyColors(themeStore.themeState.value.currentTheme.tokens.color)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        viewScope?.launch {
            themeStore.themeState.collectLatest { state ->
                applyColors(state.currentTheme.tokens.color)
            }
        }
        startMembershipRefresh()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        viewScope?.cancel()
        viewScope = null
        membershipJob = null
    }

    /** Re-reads the group-bound store whenever membership changes (add/remove-from-group pushes no event). */
    private fun startMembershipRefresh() {
        val store = membershipStore ?: return
        val scope = viewScope ?: return
        membershipJob?.cancel()
        membershipJob = scope.launch {
            ConversationGroupMembership.changes.collect {
                store.loadConversations(loadOption?.copy() ?: ConversationLoadOption(), null)
            }
        }
    }

    private fun applyColors(colors: ColorTokens) {
        // Same surface as the conversation rows (bgColorTopBar), so header, search bar and
        // list read as one sheet (design S1/S2).
        setBackgroundColor(colors.bgColorTopBar)
        appBarLayout.setBackgroundColor(colors.bgColorTopBar)
        searchBarWrapper.setBackgroundColor(colors.bgColorTopBar)
        searchBarBgDrawable.setColor(colors.bgColorInput)
        searchIcon.setColorFilter(colors.textColorTertiary)
        searchText.setTextColor(colors.textColorTertiary)
    }

    private fun setSearchBarVisible(visible: Boolean) {
        searchBarWrapper.visibility = if (visible) VISIBLE else GONE
        appBarLayout.visibility = if (visible || topContentView != null) VISIBLE else GONE
    }

    /**
     * Optional block placed under the search bar inside the collapsing area, so it scrolls
     * away together with the list (design S1: entry row + group header above the chats).
     */
    private fun setTopContent(view: View?) {
        topContentView?.let { appBarLayout.removeView(it) }
        topContentView = view
        if (view != null) {
            appBarLayout.addView(
                view,
                AppBarLayout.LayoutParams(
                    AppBarLayout.LayoutParams.MATCH_PARENT,
                    AppBarLayout.LayoutParams.WRAP_CONTENT
                ).apply { scrollFlags = AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL }
            )
        }
    }

    @JvmOverloads
    fun setup(
        config: ConversationActionConfigProtocol = ChatConversationActionConfig(),
        showSearchBar: Boolean = true,
        headerTitle: String? = null,
        headerRightAction: View? = null,
        conversationExclusion: ConversationMatcher? = null,
        conversationGroup: String? = null,
        onConversationClick: ((ConversationInfo) -> Unit)? = null,
        onSearchClick: (() -> Unit)? = null,
        emptyHint: String? = null,
        showHeader: Boolean = true,
        searchHint: String? = null,
        topContent: View? = null,
        loadOption: ConversationLoadOption? = null,
        swipeToReveal: Boolean = true,
        titleAccessory: ((ConversationInfo) -> View?)? = null
    ) {
        this.onSearchClick = onSearchClick
        this.loadOption = loadOption
        // The host may draw its own page header (scene shell); hide this one in that case.
        pageHeader.visibility = if (showHeader) VISIBLE else GONE
        searchHint?.let { searchText.text = it }
        setTopContent(topContent)
        setSearchBarVisible(showSearchBar)
        headerTitle?.let { pageHeader.setTitle(it) }
        headerRightAction?.let { pageHeader.setEditContent(it) }
        emptyHint?.let { conversationListView.setEmptyHint(it) }
        conversationListView.swipeToReveal = swipeToReveal
        val store = ConversationListStore.create(conversationGroup)
        membershipStore = store.takeIf { ConversationGroupMembership.isCustomGroup(conversationGroup) }
        conversationListView.setup(
            config = config,
            conversationExclusion = ConversationGroupMembership.exclusion(conversationGroup, conversationExclusion),
            conversationStore = store,
            onConversationClick = onConversationClick ?: {},
            loadOption = loadOption,
            titleAccessory = titleAccessory
        )
        startMembershipRefresh()
    }

    fun refreshExclusion() {
        conversationListView.refreshExclusion()
    }
}
