package io.trtc.tuikit.chat.home.ui

import android.animation.ObjectAnimator
import android.content.Context
import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.view.doOnNextLayout
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import io.trtc.tuikit.atomicx.common.util.ComponentUsage
import io.trtc.tuikit.chat.home.HomeKit
import io.trtc.tuikit.chat.home.ProfileActivity
import io.trtc.tuikit.chat.home.R
import io.trtc.tuikit.chat.hostbase.SocialToast
import io.trtc.tuikit.chat.home.data.HomeFeed
import io.trtc.tuikit.chat.home.data.HomeUserCard
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostImage
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.HostSegBar
import io.trtc.tuikit.chat.hostbase.HostSwipePager
import io.trtc.tuikit.chat.hostbase.HostStateView
import io.trtc.tuikit.chat.hostbase.HostThread
import io.trtc.tuikit.chat.hostbase.Motion
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.hostbase.SquareFrameLayout
import io.trtc.tuikit.chat.hostbase.TagKind

/**
 * Home tab. The grid is a RecyclerView (only the visible cards exist as views), pull-to-refresh replaces the first page,
 * and the next page is requested while the user is still [PRELOAD_ROWS] rows away from the end. Each section keeps its
 * own list, cursor and load state, so switching sections never refetches.
 */
class HomeView(context: Context) : LinearLayout(context) {
    private class SectionState(var cards: List<HomeUserCard>, var cursor: String?) {
        var loadingMore = false
        var loadMoreFailed = false
        var refreshing = false
        var generation = 0
    }

    private enum class FooterKind { IDLE, LOADING, END, ERROR }

    private var feed: HomeFeed? = null
    private val states = HashMap<String, SectionState>()
    private var activeSection = 0

    private val tokens get() = DemoUi.tokens
    private val state = HostStateView.asContent(context)
    private var segBar: HostSegBar? = null
    private var alive = true
    private var leaving = false

    /**
     * One list per section, built the first time the section is shown and afterwards only hidden / shown again, so
     * switching sections never re-binds cards or reloads pictures and each section keeps its scroll position.
     */
    private inner class Page(val sectionId: String) {
        val adapter = FeedAdapter(sectionId)
        val grid = GridLayoutManager(context, 2).apply {
            spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
                override fun getSpanSize(position: Int) = if (adapter.typeAt(position) == TYPE_CARD) 1 else 2
            }
        }
        val recycler = RecyclerView(context).apply {
            layoutManager = grid
            adapter = this@Page.adapter
            itemAnimator = null
            overScrollMode = OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            setItemViewCacheSize(6)
            addItemDecoration(CardSpacing(this@Page.adapter))
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(view: RecyclerView, dx: Int, dy: Int) {
                    if (dy > 0 && activeId == sectionId) loadMoreIfNeeded()
                }
            })
        }
        val swipe = SwipeRefreshLayout(context).apply {
            setColorSchemeColors(tokens.buttonColorPrimaryDefault)
            setProgressBackgroundColorSchemeColor(tokens.bgColorOperate)
            setOnRefreshListener { reload() }
            addView(recycler, ViewGroup.LayoutParams(-1, -1))
        }
    }

    private val pages = HashMap<String, Page>()
    private var pager: HostSwipePager? = null
    private var pendingStagger = false
    private val activePage get() = activeId?.let { pages[it] }

    init {
        orientation = VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        load()
        ComponentUsage.report(ComponentUsage.SOCIAL_HOME)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        alive = false
    }

    private val activeId get() = feed?.sections?.getOrNull(activeSection)?.id
    private val active get() = activeId?.let { states[it] }

    private fun load() {
        showShell(null)
        state.showLoading()
        HomeKit.dataSource.loadFeed { result ->
            HostThread.runOnMain {
                if (!alive) return@runOnMain
                result.onSuccess { loaded ->
                    feed = loaded
                    states.clear()
                    pages.clear()
                    loaded.sections.forEach { states[it.id] = SectionState(it.cards, it.nextCursor) }
                    activeSection = 0
                    showShell(loaded)
                    showActive(stagger = true)
                }.onFailure {
                    state.showError { load() }
                }
            }
        }
    }

    private fun showShell(loaded: HomeFeed?) {
        removeAllViews()
        (state.parent as? android.view.ViewGroup)?.removeView(state)
        if (loaded == null) {
            segBar = null
            pager = null
            addView(state, LayoutParams(-1, 0, 1f))
            return
        }
        val bar = HostSegBar(context, loaded.sections.map { it.title }, activeSection, tight = true) { index ->
            if (index == activeSection) return@HostSegBar
            activeSection = index
            // Already built sections slide back in untouched; a new one is built once and slides in.
            showActive(stagger = false, animate = true)
        }
        segBar = bar
        addView(bar)
        val frame = FrameLayout(context)
        val swiper = HostSwipePager(context).apply {
            pageCount = loaded.sections.size
            provider = { position -> createPage(position).swipe }
            // The tab bar travels with the pages (tap slide, drag and settle), see HostSegBar.setPosition.
            onProgress = { position -> segBar?.setPosition(position) }
            onSwiped = { position ->
                activeSection = position
                updateStateView()
                activePage?.recycler?.post { loadMoreIfNeeded() }
            }
        }
        pager = swiper
        frame.addView(swiper, FrameLayout.LayoutParams(-1, -1))
        frame.addView(state, FrameLayout.LayoutParams(-1, -1))
        addView(frame, LayoutParams(-1, 0, 1f))
    }

    private fun visibleCards(): List<View> {
        val list = activePage?.recycler ?: return emptyList()
        return (0 until list.childCount).map { list.getChildAt(it) }.filter { list.getChildViewHolder(it) is CardHolder }
    }

    private fun leaveThen(next: () -> Unit) {
        if (leaving) return
        val cards = visibleCards()
        if (cards.isEmpty() || !Motion.enabled(context)) {
            next()
            return
        }
        leaving = true
        cards.forEach { Motion.cardLeave(it) }
        postDelayed({
            leaving = false
            if (alive) next()
        }, 200)
    }

    private fun createPage(position: Int): Page {
        val id = feed?.sections?.getOrNull(position)?.id.orEmpty()
        val page = Page(id)
        pages[id] = page
        fill(page, pendingStagger)
        return page
    }

    /**
     * Shows the active section. Its list is built once; later visits only slide it back in (nothing is rebound or
     * refetched). [stagger] plays the card entrance for a freshly built list, [animate] slides between sections.
     */
    private fun showActive(stagger: Boolean, animate: Boolean = false) {
        val host = pager ?: return
        pendingStagger = stagger
        host.show(activeSection, animate)
        updateStateView()
        activePage?.recycler?.post { loadMoreIfNeeded() }
    }

    /** Replaces a section's list with its saved state (first build, pull-to-refresh and 换一批) and scrolls to the top. */
    private fun fill(page: Page, stagger: Boolean) {
        page.adapter.staggerNext = stagger && Motion.enabled(context)
        if (page.adapter.staggerNext) page.recycler.doOnNextLayout { page.adapter.staggerNext = false }
        page.adapter.notifyDataSetChanged()
        page.recycler.scrollToPosition(0)
    }

    private fun updateStateView() {
        if (active?.cards.isNullOrEmpty()) state.showEmpty() else state.hide()
    }

    /** Pull-to-refresh and "换一批" both end here: a fresh first page replaces the list, whatever the outcome. */
    private fun reload() {
        val sectionId = activeId ?: return
        val section = states[sectionId] ?: return
        if (section.refreshing) return
        section.refreshing = true
        section.loadingMore = false
        section.loadMoreFailed = false
        section.generation++
        HomeKit.dataSource.refresh(sectionId) { result ->
            HostThread.runOnMain {
                section.refreshing = false
                if (!alive) return@runOnMain
                result.onSuccess { page ->
                    if (page.cards.isNotEmpty()) {
                        section.cards = distinct(page.cards)
                        section.cursor = page.nextCursor
                    }
                }.onFailure {
                    if (activeId == sectionId) SocialToast.show(context, DemoText.get(R.string.demo_refresh_failed), SocialToast.Kind.ERROR)
                }
                pages[sectionId]?.let { page ->
                    page.swipe.isRefreshing = false
                    fill(page, stagger = activeId == sectionId)
                    if (activeId == sectionId) updateStateView()
                }
            }
        }
    }

    private fun distinct(cards: List<HomeUserCard>): List<HomeUserCard> {
        val seen = HashSet<String>()
        return cards.filter { seen.add(it.id) }
    }

    private fun loadMoreIfNeeded() {
        val section = active ?: return
        if (section.cursor == null || section.loadingMore || section.loadMoreFailed || section.refreshing) return
        if (section.cards.isEmpty()) return
        val page = activePage ?: return
        val last = page.grid.findLastVisibleItemPosition()
        if (last < 0 || last < page.adapter.itemCount - 1 - PRELOAD_ROWS * 2) return
        loadMore()
    }

    private fun loadMore() {
        val sectionId = activeId ?: return
        val section = states[sectionId] ?: return
        val cursor = section.cursor ?: return
        if (section.loadingMore) return
        section.loadingMore = true
        section.loadMoreFailed = false
        val generation = section.generation
        pages[sectionId]?.adapter?.footerChanged(section)
        HomeKit.dataSource.loadMore(sectionId, cursor) { result ->
            HostThread.runOnMain {
                if (!alive || generation != section.generation) return@runOnMain
                section.loadingMore = false
                result.onSuccess { page ->
                    val known = section.cards.mapTo(HashSet()) { it.id }
                    val fresh = page.cards.filter { known.add(it.id) }
                    // A page with nothing new ends the list, so a source that repeats itself cannot loop forever.
                    section.cursor = if (fresh.isEmpty()) null else page.nextCursor
                    val before = section.cards.size
                    section.cards = section.cards + fresh
                    pages[sectionId]?.adapter?.appended(before, fresh.size, section)
                }.onFailure {
                    section.loadMoreFailed = true
                    pages[sectionId]?.adapter?.footerChanged(section)
                }
                if (activeId == sectionId) activePage?.recycler?.post { loadMoreIfNeeded() }
            }
        }
    }

    private fun footerKind(section: SectionState?) = when {
        section == null -> FooterKind.IDLE
        section.loadMoreFailed -> FooterKind.ERROR
        section.loadingMore -> FooterKind.LOADING
        section.cursor == null -> FooterKind.END
        else -> FooterKind.IDLE
    }

    private inner class CardSpacing(private val adapter: FeedAdapter) : RecyclerView.ItemDecoration() {
        private val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        private val gap = Host.dp(context, HostMetrics.USER_CARD_GAP)

        override fun getItemOffsets(outRect: android.graphics.Rect, view: View, parent: RecyclerView, state: RecyclerView.State) {
            val position = parent.getChildAdapterPosition(view)
            if (position == RecyclerView.NO_POSITION || adapter.typeAt(position) != TYPE_CARD) return
            val left = (view.layoutParams as GridLayoutManager.LayoutParams).spanIndex == 0
            outRect.left = if (left) pad else gap / 2
            outRect.right = if (left) gap / 2 else pad
            outRect.bottom = gap
        }
    }

    private inner class FeedAdapter(private val sectionId: String) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        private val section get() = states[sectionId]
        private val cards get() = section?.cards.orEmpty()
        var staggerNext = false

        fun typeAt(position: Int) = when {
            position == 0 -> TYPE_HEAD
            position == itemCount - 1 && cards.isNotEmpty() -> TYPE_FOOTER
            else -> TYPE_CARD
        }

        override fun getItemCount() = if (section == null) 0 else if (cards.isEmpty()) 1 else cards.size + 2

        override fun getItemViewType(position: Int) = typeAt(position)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder = when (viewType) {
            TYPE_HEAD -> HeadHolder(sectionHead())
            TYPE_FOOTER -> FooterHolder(FrameLayout(context).apply {
                layoutParams = RecyclerView.LayoutParams(-1, -2)
            })
            else -> CardHolder()
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            when (holder) {
                is CardHolder -> {
                    val index = position - 1
                    holder.bind(cards[index])
                    if (staggerNext && index < STAGGER_LIMIT) Motion.rowIn(holder.itemView, Motion.gridDelay(index), Motion.SLOW)
                }
                is FooterHolder -> holder.bind(footerKind(section))
                else -> Unit
            }
        }

        override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
            if (holder is CardHolder) holder.reset()
        }

        fun appended(before: Int, count: Int, section: SectionState) {
            if (count > 0) notifyItemRangeInserted(before + 1, count)
            footerChanged(section)
        }

        fun footerChanged(section: SectionState) {
            if (section.cards.isNotEmpty()) notifyItemChanged(itemCount - 1)
        }
    }

    private inner class HeadHolder(view: View) : RecyclerView.ViewHolder(view)

    private inner class FooterHolder(private val frame: FrameLayout) : RecyclerView.ViewHolder(frame) {
        fun bind(kind: FooterKind) {
            frame.removeAllViews()
            frame.setOnClickListener(null)
            frame.isClickable = false
            val c = tokens
            when (kind) {
                FooterKind.IDLE -> frame.addView(View(context), FrameLayout.LayoutParams(-1, Host.dp(context, 24)))
                else -> {
                    val label = when (kind) {
                        FooterKind.LOADING -> DemoText.get(BaseR.string.demo_loading)
                        FooterKind.ERROR -> DemoText.get(BaseR.string.demo_load_failed_tap_to_retry)
                        else -> DemoText.get(R.string.demo_no_more_people)
                    }
                    frame.addView(Host.text(context, label, 12f, c.textColorTertiary).apply { gravity = Gravity.CENTER },
                        FrameLayout.LayoutParams(-1, Host.dp(context, 56)))
                    if (kind == FooterKind.ERROR) frame.setOnClickListener {
                        active?.let { section ->
                            section.loadMoreFailed = false
                            loadMore()
                        }
                    }
                }
            }
        }
    }

    private fun sectionHead(): View {
        val c = tokens
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        return LinearLayout(context).apply {
            layoutParams = RecyclerView.LayoutParams(-1, -2)
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(c.bgColorTopBar)
            setPadding(pad, Host.dp(context, 10), pad, Host.dp(context, 8))
            addView(Host.text(context, DemoText.get(BaseR.string.demo_recommended_for_you), 13f, c.textColorTertiary, bold = true), LayoutParams(0, -2, 1f))
            val refresh = Host.icon(context, R.drawable.demo_ic_refresh, 12, c.textColorTertiary)
            addView(LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(refresh)
                addView(Host.text(context, DemoText.get(R.string.demo_refresh), 12f, c.textColorTertiary), LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 4) })
                contentDescription = DemoText.get(R.string.demo_refresh)
                setOnClickListener {
                    if (leaving || active?.refreshing == true) return@setOnClickListener
                    ObjectAnimator.ofFloat(refresh, View.ROTATION, 0f, 360f).setDuration(360).start()
                    leaveThen { reload() }
                }
            })
        }
    }

    private inner class CardHolder private constructor(private val root: LinearLayout) : RecyclerView.ViewHolder(root) {
        constructor() : this(LinearLayout(context))

        private var card: HomeUserCard? = null
        private val image = ImageView(context).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
        private val cityTag = Host.kindTag(context, TagKind.CITY, "")
        private val heightTag = Host.kindTag(context, TagKind.HEIGHT, "")
        private val metaRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(cityTag)
            addView(heightTag, LinearLayout.LayoutParams(-2, Host.dp(context, HostMetrics.DIST_TAG_H)).apply {
                marginStart = Host.dp(context, 4)
            })
        }
        private val name = Host.text(context, "", HostMetrics.USER_CARD_NAME_SP, tokens.textColorPrimary, bold = true, single = true)
        private val sexSlot = FrameLayout(context)
        private val meta = Host.text(context, "", HostMetrics.USER_CARD_META_SP, tokens.textColorTertiary, single = true)

        init {
            val c = tokens
            root.apply {
                layoutParams = RecyclerView.LayoutParams(-1, -2)
                orientation = VERTICAL
                background = Host.rounded(context, c.bgColorOperate, HostMetrics.CARD_RADIUS.toFloat())
                Host.roundedClip(this, HostMetrics.CARD_RADIUS.toFloat())
                setOnClickListener {
                    val current = card ?: return@setOnClickListener
                    context.startActivity(Intent(context, ProfileActivity::class.java).putExtra(ProfileActivity.EXTRA_USER_KEY, current.id))
                }
            }
            root.addView(photo(), LayoutParams(-1, -2))
            root.addView(LinearLayout(context).apply {
                orientation = VERTICAL
                setPadding(Host.dp(context, 10), Host.dp(context, 8), Host.dp(context, 10), Host.dp(context, 10))
                addView(LinearLayout(context).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(name, LayoutParams(0, -2, 1f))
                    addView(sexSlot, LayoutParams(-2, Host.dp(context, HostMetrics.SEX_TAG_H)).apply { marginStart = Host.dp(context, 4) })
                })
                addView(meta, LayoutParams(-1, -2).apply { topMargin = Host.dp(context, 4) })
            })
        }

        fun bind(value: HomeUserCard) {
            reset()
            card = value
            HostImage.bind(image, value.photo)
            image.contentDescription = value.displayName
            val heightText = if (value.height > 0) DemoText.get(BaseR.string.demo_height_cm, value.height.toString()) else ""
            cityTag.text = value.city
            cityTag.visibility = if (value.city.isBlank()) View.GONE else View.VISIBLE
            heightTag.text = heightText
            heightTag.visibility = if (heightText.isBlank()) View.GONE else View.VISIBLE
            metaRow.visibility = if (cityTag.visibility == View.GONE && heightTag.visibility == View.GONE) View.GONE else View.VISIBLE
            name.text = value.displayName
            sexSlot.removeAllViews()
            sexSlot.addView(Host.sexTag(context, value.sex, value.age), FrameLayout.LayoutParams(-2, -1))
            meta.text = (value.tags + listOfNotNull(value.activity.takeIf { it.isNotBlank() })).joinToString(" · ")
        }

        fun reset() {
            root.animate().cancel()
            root.alpha = 1f
            root.scaleX = 1f
            root.scaleY = 1f
            root.translationY = 0f
        }

        private fun photo(): View {
            val c = tokens
            return SquareFrameLayout(context).apply {
                setBackgroundColor(c.bgColorFunction)
                addView(image, FrameLayout.LayoutParams(-1, -1))
                addView(View(context).apply {
                    background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                        intArrayOf(0x00000000, 0xAD000000.toInt()))
                }, FrameLayout.LayoutParams(-1, Host.dp(context, HostMetrics.USER_CARD_MASK_H), Gravity.BOTTOM))
                addView(metaRow, FrameLayout.LayoutParams(-2, Host.dp(context, HostMetrics.DIST_TAG_H), Gravity.TOP or Gravity.START).apply {
                    leftMargin = Host.dp(context, 8)
                    topMargin = Host.dp(context, 8)
                })
            }
        }
    }

    private companion object {
        const val TYPE_HEAD = 0
        const val TYPE_CARD = 1
        const val TYPE_FOOTER = 2
        const val PRELOAD_ROWS = 3
        const val STAGGER_LIMIT = 10
    }
}
