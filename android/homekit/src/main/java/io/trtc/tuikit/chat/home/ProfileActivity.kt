package io.trtc.tuikit.chat.home

import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.viewpager.widget.PagerAdapter
import io.trtc.tuikit.chat.home.R
import io.trtc.tuikit.chat.home.data.HomeUserCard
import io.trtc.tuikit.chat.home.data.HomeUserDetail
import io.trtc.tuikit.chat.home.ui.CoverCarousel
import io.trtc.tuikit.chat.home.ui.CoverIndicator
import io.trtc.tuikit.chat.home.ui.CoverViewPager
import io.trtc.tuikit.chat.home.ui.FriendActionButton
import io.trtc.tuikit.chat.home.ui.ProfileUi
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostHeader
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.HostStateView
import io.trtc.tuikit.chat.hostbase.HostThread
import io.trtc.tuikit.chat.hostbase.Motion
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.hostbase.SquareFrameLayout
import io.trtc.tuikit.chat.hostbase.TagKind

/**
 * Other-person profile (design B5 `527:2357`): header with back + name, square
 * cover (bottom mask, page dots), identity block (name, 女 23, 实名, meta, voice sign,
 * bio, interest tags), 缘分值 row, four facts, album preview, the moments list and the sticky 去聊天 / 视频聊聊 bar.
 * All values come from HomeKit's HomeDataSource (loadUserDetail); the two sticky actions are delegated to HomeActions.
 */
class ProfileActivity : DemoActivity() {
    private lateinit var card: HomeUserCard
    private lateinit var page: LinearLayout
    private lateinit var body: FrameLayout
    private lateinit var state: HostStateView
    private var userKey = ""
    private var alive = true
    private val tokens get() = DemoUi.tokens
    private var carousel: CoverCarousel? = null
    private var resumed = false
    private var friendAction: FriendActionButton? = null
    private var friendNow = false

    companion object {
        const val EXTRA_USER_KEY = "userKey"
        const val EXTRA_FROM_CHAT = "fromChat"
        const val COVER_ALBUM_PAGES = 3
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        carousel?.start()
        refreshFriendAction()
    }

    override fun onPause() {
        resumed = false
        carousel?.stop()
        super.onPause()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        userKey = intent.getStringExtra(EXTRA_USER_KEY) ?: return finish()
        page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(tokens.bgColorTopBar)
        }
        setContentView(page)
        immersive(page, tokens.bgColorTopBar, bodyColor = tokens.bgColorTopBar)
        load()
    }

    override fun onDestroy() {
        super.onDestroy()
        alive = false
        carousel?.stop()
        carousel = null
    }

    private fun load() {
        page.removeAllViews()
        page.addView(HostHeader(this, "", left = backButton()))
        state = HostStateView.asContent(this)
        body = FrameLayout(this).apply { setBackgroundColor(tokens.bgColorDefault) }
        body.addView(state)
        page.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        HomeKit.cachedDetail(userKey)?.let { return show(it) }
        state.showLoading()
        HomeKit.dataSource.loadUserDetail(userKey) { result ->
            HostThread.runOnMain {
                if (!alive) return@runOnMain
                result.onSuccess {
                    HomeKit.cacheDetail(userKey, it)
                    show(it)
                }.onFailure { state.showError { load() } }
            }
        }
    }

    private fun show(detail: HomeUserDetail) {
        card = detail.card
        page.removeAllViews()
        page.addView(header(card))
        refreshFriendAction()
        page.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            setBackgroundColor(tokens.bgColorDefault)
            addView(content(card, detail))
        }, LinearLayout.LayoutParams(-1, 0, 1f))
        page.addView(stickyBar())
    }

    private fun backButton() = Host.backButton(this) { finish() }

    private fun header(card: HomeUserCard): View {
        val action = FriendActionButton(this).apply {
            render(friend = false)
            visibility = View.INVISIBLE
            setOnClickListener { onFriendAction() }
        }
        friendAction = action
        return HostHeader(this, card.displayName, left = backButton(), ops = listOf(action))
    }

    /** Non-friend: send the preset friend request. Friend: the grey friend icon asks before deleting. */
    private fun onFriendAction() {
        if (!::card.isInitialized) return
        if (friendNow) {
            confirmDeleteFriend()
        } else {
            HomeKit.actions.onAddFriend(this, card) { outcome ->
                if (outcome != FriendAddOutcome.ADDED) return@onAddFriend
                HostThread.runOnMain {
                    if (!alive) return@runOnMain
                    // Set the state directly: the friend list may not have synced yet for a re-query.
                    friendNow = true
                    friendAction?.render(friend = true, animate = true)
                }
            }
        }
    }

    private fun confirmDeleteFriend() {
        Host.showThemed(this, android.app.AlertDialog.Builder(this)
            .setTitle(DemoText.get(R.string.demo_delete_friend))
            .setMessage(DemoText.get(R.string.demo_delete_friend_message))
            .setNegativeButton(DemoText.get(BaseR.string.demo_cancel), null)
            .setPositiveButton(DemoText.get(R.string.demo_delete)) { _, _ ->
                HomeKit.actions.onDeleteFriend(this, card) { deleted ->
                    HostThread.runOnMain {
                        if (!alive || !deleted) return@runOnMain
                        // Same as the add path: reflect the known state instead of re-querying before sync.
                        friendNow = false
                        friendAction?.render(friend = false, animate = true)
                    }
                }
            }, positiveColor = tokens.textColorError)
    }

    private fun refreshFriendAction() {
        val view = friendAction ?: return
        if (!::card.isInitialized || card.userId.isBlank()) {
            view.visibility = View.GONE
            return
        }
        HomeKit.actions.isFriend(this, card) { friend ->
            HostThread.runOnMain {
                if (!alive) return@runOnMain
                friendNow = friend
                view.render(friend)
                view.visibility = View.VISIBLE
            }
        }
    }

    private fun content(card: HomeUserCard, profile: HomeUserDetail?) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        addView(cover(card, profile))
        addView(identity(card, profile))
        if (profile != null) {
            if (profile.matchScore > 0) {
                addView(gap())
                addView(matchRow(profile))
            }
            if (profile.facts.isNotEmpty()) addView(facts(profile))
            if (profile.albumPhotos.isNotEmpty()) {
                addView(gap())
                addView(albumPreview(profile))
            }
            addView(gap())
            addView(moments(profile))
        }
        addView(View(this@ProfileActivity), LinearLayout.LayoutParams(-1, Host.dp(this@ProfileActivity, 16)))
    }

    private fun gap() = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(-1, Host.dp(this@ProfileActivity, 8))
    }

    /** Cover pages: the card photo first, then the first [COVER_ALBUM_PAGES] album photos. */
    private fun coverPages(card: HomeUserCard, profile: HomeUserDetail?): List<String> =
        (listOf(card.photo) + profile?.albumPhotos.orEmpty().take(COVER_ALBUM_PAGES)).filter { it.isNotBlank() }.distinct()

    /** `.cover`: square swipeable photo pager (360 on the design frame), 140dp bottom mask, one page dot per photo. */
    private fun cover(card: HomeUserCard, profile: HomeUserDetail?): View = SquareFrameLayout(this).apply {
        setBackgroundColor(tokens.bgColorFunction)
        val pages = coverPages(card, profile).ifEmpty { listOf(card.photo) }
        val total = pages.size
        val looping = total > 1
        val pager = CoverViewPager(this@ProfileActivity).apply {
            adapter = object : PagerAdapter() {
                override fun getCount() = if (looping) CoverCarousel.LOOP_COUNT else 1
                override fun isViewFromObject(view: View, any: Any) = view === any
                override fun instantiateItem(container: android.view.ViewGroup, position: Int): Any =
                    ProfileUi.photo(this@ProfileActivity, pages[position % total]).also {
                        it.contentDescription = DemoText.get(R.string.demo_view_album)
                        it.setOnClickListener { openAlbum() }
                        container.addView(it)
                    }
                override fun destroyItem(container: android.view.ViewGroup, position: Int, any: Any) =
                    container.removeView(any as View)
            }
            if (looping) setCurrentItem(CoverCarousel.startPosition(total), false)
        }
        addView(pager, FrameLayout.LayoutParams(-1, -1))
        pager.post { Motion.kenBurns(pager) }
        addView(View(this@ProfileActivity).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0x00000000, 0xE005030D.toInt()))
        }, FrameLayout.LayoutParams(-1, Host.dp(this@ProfileActivity, 140), Gravity.BOTTOM))
        val indicator = CoverIndicator(this@ProfileActivity).apply {
            count = total
            visibility = if (looping) View.VISIBLE else View.GONE
        }
        addView(indicator, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = Host.dp(this@ProfileActivity, 16)
        })
        carousel?.stop()
        carousel = CoverCarousel(pager, total, indicator).also { if (resumed) it.start() }
    }

    /** `.ident`: padding 14/16/16, gap 8 on the top-bar surface. */
    private fun identity(card: HomeUserCard, profile: HomeUserDetail?) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        val pad = Host.dp(this@ProfileActivity, HostMetrics.SCREEN_PADDING_H)
        setPadding(pad, Host.dp(this@ProfileActivity, 14), pad, pad)
        addView(LinearLayout(this@ProfileActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(Host.text(this@ProfileActivity, card.displayName, 22f, tokens.textColorPrimary, bold = true))
            addView(ProfileUi.solidSexTag(this@ProfileActivity, card.sex, card.age),
                LinearLayout.LayoutParams(-2, Host.dp(this@ProfileActivity, 20)).apply { marginStart = Host.dp(this@ProfileActivity, 8) })
            if (card.height > 0) {
                addView(Host.kindTag(this@ProfileActivity, TagKind.HEIGHT, DemoText.get(BaseR.string.demo_height_cm, card.height.toString()),
                    20, 10f, 11f),
                    LinearLayout.LayoutParams(-2, Host.dp(this@ProfileActivity, 20)).apply { marginStart = Host.dp(this@ProfileActivity, 8) })
            }
            addView(Host.verifiedTag(this@ProfileActivity, DemoText.get(BaseR.string.demo_verified)),
                LinearLayout.LayoutParams(-2, Host.dp(this@ProfileActivity, 18)).apply { marginStart = Host.dp(this@ProfileActivity, 8) })
        })
        val rawMeta = profile?.meta?.takeIf { it.isNotBlank() } ?: card.city
        val meta = rawMeta.split(" · ").filterNot { it.matches(Regex("^\\d+(\\.\\d+)?km$")) }.joinToString(" · ")
        addView(Host.text(this@ProfileActivity, meta, 12f, tokens.textColorSecondary),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(this@ProfileActivity, 8) })
        if (profile != null && profile.voiceSeconds > 0) {
            addView(ProfileUi.voiceButton(this@ProfileActivity, profile.voiceSeconds), LinearLayout.LayoutParams(-1, Host.dp(this@ProfileActivity, 36)).apply { topMargin = Host.dp(this@ProfileActivity, 8) })
        }
        val bio = profile?.bio?.takeIf { it.isNotBlank() } ?: card.bio
        addView(Host.text(this@ProfileActivity, bio, 14f, tokens.textColorPrimary).apply {
            setLineSpacing(Host.dpf(this@ProfileActivity, 7f), 1f)
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(this@ProfileActivity, 8) })
        val interests = profile?.interests.orEmpty()
        if (interests.isNotEmpty()) {
            addView(LinearLayout(this@ProfileActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                interests.forEachIndexed { index, item ->
                    addView(ProfileUi.interestTag(this@ProfileActivity, item.text, item.level),
                        LinearLayout.LayoutParams(-2, Host.dp(this@ProfileActivity, 26)).apply {
                            if (index > 0) marginStart = Host.dp(this@ProfileActivity, 8)
                        })
                }
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(this@ProfileActivity, 8) })
        }
    }

    /** `.matchrow`: warning-tinted 「缘分值 92」 pill + sentence on the top-bar surface. */
    private fun matchRow(profile: HomeUserDetail) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        val pad = Host.dp(this@ProfileActivity, HostMetrics.SCREEN_PADDING_H)
        setPadding(pad, Host.dp(this@ProfileActivity, 10), pad, Host.dp(this@ProfileActivity, 10))
        addView(Host.text(this@ProfileActivity, DemoText.get(R.string.demo_match, profile.matchScore), 11f, tokens.textColorWarning, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(Host.dp(this@ProfileActivity, 10), 0, Host.dp(this@ProfileActivity, 10), 0)
            background = Host.rounded(this@ProfileActivity, Host.alpha(tokens.textColorWarning, 0.16f), 12f)
        }, LinearLayout.LayoutParams(-2, Host.dp(this@ProfileActivity, 24)))
        addView(Host.text(this@ProfileActivity, profile.matchText, 12f, tokens.textColorSecondary, single = true),
            LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = Host.dp(this@ProfileActivity, 8) })
    }

    /** `.facts`: four equal columns, value 16 bold over label 11 tertiary. */
    private fun facts(profile: HomeUserDetail) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setBackgroundColor(tokens.bgColorTopBar)
        val pad = Host.dp(this@ProfileActivity, HostMetrics.SCREEN_PADDING_H)
        setPadding(pad, Host.dp(this@ProfileActivity, 12), pad, Host.dp(this@ProfileActivity, 12))
        profile.facts.forEach { fact ->
            addView(LinearLayout(this@ProfileActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                addView(Host.text(this@ProfileActivity, fact.value, 16f, tokens.textColorPrimary, bold = true),
                    LinearLayout.LayoutParams(-2, -2))
                addView(Host.text(this@ProfileActivity, fact.label, 11f, tokens.textColorTertiary),
                    LinearLayout.LayoutParams(-2, -2).apply { topMargin = Host.dp(this@ProfileActivity, 4) })
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }
    }

    /** `.albumprev`: 「相册 12」 head + 4 thumbs (h76, r8, gap 8), the third carries a 24dp play badge. */
    private fun albumPreview(profile: HomeUserDetail) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        val pad = Host.dp(this@ProfileActivity, HostMetrics.SCREEN_PADDING_H)
        setPadding(pad, Host.dp(this@ProfileActivity, 14), pad, Host.dp(this@ProfileActivity, 14))
        addView(ProfileUi.blockHead(this@ProfileActivity, DemoText.get(R.string.demo_album), profile.albumCount) { openAlbum() })
        addView(LinearLayout(this@ProfileActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            profile.albumPhotos.take(4).forEachIndexed { index, name ->
                addView(ProfileUi.thumb(this@ProfileActivity, name, 8f, if (index == 2) 24 else 0).apply {
                    setOnClickListener { openAlbum() }
                }, LinearLayout.LayoutParams(0, Host.dp(this@ProfileActivity, 76), 1f).apply {
                    if (index > 0) marginStart = Host.dp(this@ProfileActivity, 8)
                })
            }
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(this@ProfileActivity, 10) })
    }

    /** `.plist`: 「动态 N」 head (no 「全部」 link, the posts live right here) then post cards or the empty line. */
    private fun moments(profile: HomeUserDetail) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        val pad = Host.dp(this@ProfileActivity, HostMetrics.SCREEN_PADDING_H)
        setPadding(pad, Host.dp(this@ProfileActivity, 14), pad, Host.dp(this@ProfileActivity, 16))
        addView(ProfileUi.blockHead(this@ProfileActivity, DemoText.get(R.string.demo_moments), profile.posts.size, null))
        if (profile.posts.isEmpty()) {
            addView(Host.text(this@ProfileActivity, DemoText.get(R.string.demo_they_haven_t_posted_any_moments_yet), 12f, tokens.textColorTertiary).apply {
                gravity = Gravity.CENTER
                setPadding(0, Host.dp(this@ProfileActivity, 28), 0, Host.dp(this@ProfileActivity, 28))
            }, LinearLayout.LayoutParams(-1, -2))
        }
        profile.posts.forEach { post ->
            addView(ProfileUi.postCard(this@ProfileActivity, card, post),
                LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(this@ProfileActivity, 10) })
        }
    }

    /** `.stickyops`: 去聊天 (function surface) and 视频聊聊 (brand), 44dp pills. */
    private fun stickyBar() = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setBackgroundColor(tokens.bgColorTopBar)
        val pad = Host.dp(this@ProfileActivity, HostMetrics.SCREEN_PADDING_H)
        setPadding(pad, Host.dp(this@ProfileActivity, 10), pad, Host.dp(this@ProfileActivity, 10))
        addView(Host.text(this@ProfileActivity, DemoText.get(R.string.demo_go_chat), 16f, tokens.textColorPrimary, bold = true).apply {
            gravity = Gravity.CENTER
            background = Host.rounded(this@ProfileActivity, tokens.bgColorFunction, 22f)
            contentDescription = DemoText.get(R.string.demo_go_chat)
            setOnClickListener { openChat() }
        }, LinearLayout.LayoutParams(0, Host.dp(this@ProfileActivity, 44), 1f))
        addView(Host.text(this@ProfileActivity, DemoText.get(R.string.demo_video_chat), 16f, tokens.textColorButton, bold = true).apply {
            gravity = Gravity.CENTER
            background = Host.rounded(this@ProfileActivity, tokens.buttonColorPrimaryDefault, 22f)
            contentDescription = DemoText.get(R.string.demo_video_chat)
            setOnClickListener { videoChat() }
        }, LinearLayout.LayoutParams(0, Host.dp(this@ProfileActivity, 44), 1f).apply {
            marginStart = Host.dp(this@ProfileActivity, 12)
        })
    }

    private fun openAlbum() {
        startActivity(Intent(this, AlbumActivity::class.java).putExtra(EXTRA_USER_KEY, userKey))
    }

    private fun openChat() {
        if (intent.getBooleanExtra(EXTRA_FROM_CHAT, false)) finish() else HomeKit.actions.onOpenChat(this, card)
    }

    private fun videoChat() = HomeKit.actions.onVideoChat(this, card)
}
