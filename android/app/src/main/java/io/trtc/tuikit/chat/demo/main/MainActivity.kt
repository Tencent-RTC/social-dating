package io.trtc.tuikit.chat.demo.main

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import io.trtc.tuikit.chat.demo.DemoSession
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.chat.ChatActivity
import io.trtc.tuikit.chat.demo.social.DemoBadgeCenter
import io.trtc.tuikit.chat.demo.social.DemoCallPromoter
import io.trtc.tuikit.chat.demo.social.DemoGroupDiagnostics
import io.trtc.tuikit.chat.demo.social.DemoGroupWatcher
import io.trtc.tuikit.chat.demo.social.DemoMessageBanner
import io.trtc.tuikit.chat.home.ui.HomeView
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.HostTabBar
import io.trtc.tuikit.chat.hostbase.Motion
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.hostbase.SocialToast
import io.trtc.tuikit.chat.mine.data.MineIdentity
import io.trtc.tuikit.chat.mine.ui.MineView
import io.trtc.tuikit.chat.uikit.components.common.AtomicCallEventPublisher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/** V2 host shell: exactly three primary tabs.
 * Home and Mine are the HomeKit / MineKit modules; Messages binds the real IM conversation list.
 */
class MainActivity : DemoActivity() {
    override val slideOnFinish: Boolean get() = false
    private lateinit var content: FrameLayout
    private lateinit var tabBar: HostTabBar
    private var messagesView: GroupedMessagesView? = null
    private var current = 0
    private var callReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val preview = intent.getBooleanExtra("preview", false)
        if (preview) {
            accountId = "PREVIEW"
            nickname = DemoText.get(R.string.demo_preview_not_logged_in)
        } else {
            val self = com.tencent.imsdk.v2.V2TIMManager.getInstance().loginUser
            accountId = self?.takeIf { it.isNotBlank() }
                ?: intent.getStringExtra("userId").orEmpty()
            nickname = accountId
            loadSelfProfile()
        }
        if (accountId.isBlank()) {
            finish()
            return
        }
        this.preview = preview
        callReady = intent.getBooleanExtra("callReady", false)
        DemoSession.accountId = accountId
        DemoSession.callReady = callReady
        DemoSession.preview = preview
        if (!preview) requestNotificationPermissionOnce()
        if (!preview) DemoGroupWatcher.ensureStarted(this, accountId)
        if (!preview) DemoCallPromoter.ensureStarted()
        build()
        // A theme change (palette / mode in 设置) rebuilds this activity; stay on the tab the user was on.
        show(savedInstanceState?.getInt(KEY_TAB, 0)?.coerceIn(0, 2) ?: 0)
        if (!preview) {
            DemoMessageBanner.ensureStarted(this, accountId)
            DemoMessageBanner.onShown = { if (::tabBar.isInitialized) tabBar.bounceBadge() }
            // Only a missing package capability needs the visible pages rebuilt so the explanation
            // replaces the empty state.
            lifecycleScope.launch {
                DemoGroupDiagnostics.changes.collect { messagesView?.onGroupStateChanged() }
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_TAB, current)
    }

    private companion object {
        const val KEY_TAB = "host_tab"
        const val PREFS = "demo_login"
        const val KEY_ASKED_NOTIFICATION = "asked_notification_permission"
    }

    private fun requestNotificationPermissionOnce() {
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_ASKED_NOTIFICATION, false)) return
        prefs.edit().putBoolean(KEY_ASKED_NOTIFICATION, true).apply()
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0x4e50)
    }

    private var accountId = ""
    private var nickname = ""
    private var preview = false
    private var avatarURL: String? = null
    private var signature = ""
    private var profileScope: kotlinx.coroutines.CoroutineScope? = null

    private fun build() {
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        setContentView(root)
        immersive(root, DemoUi.tokens.bgColorTopBar)
        if (preview) {
            root.addView(DemoUi.text(this, DemoText.get(R.string.demo_ui_preview_im_is_not_logged_in),
                11f, DemoUi.MUTED).apply {
                setPadding(DemoUi.dp(this@MainActivity, 18), DemoUi.dp(this@MainActivity, 8),
                    DemoUi.dp(this@MainActivity, 18), DemoUi.dp(this@MainActivity, 8))
                setBackgroundColor(Color.parseColor(DemoUi.SURFACE_HIGH))
            })
        }
        content = FrameLayout(this)
        root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(buildTabBar())
    }

    private fun buildTabBar(): HostTabBar {
        tabBar = HostTabBar(this, listOf(DemoText.get(BaseR.string.demo_home), DemoText.get(R.string.demo_messages), DemoText.get(BaseR.string.demo_me))) { index -> if (index != current) show(index, animate = true) }
        observeUnread()
        return tabBar
    }

    /** The bottom Messages tab shows the 消息 segment badge plus the 好友 segment badge, see [DemoBadgeCenter]. */
    private fun observeUnread() {
        if (preview) return
        DemoBadgeCenter.ensureStarted(accountId)
        lifecycleScope.launch { DemoBadgeCenter.total.collect { tabBar.setBadge(it) } }
    }

    /** The three tab pages, each built the first time its tab is opened and then only hidden / shown again. */
    private val tabViews = arrayOfNulls<View>(3)

    private fun show(index: Int, animate: Boolean = false) {
        current = index
        tabBar.select(index)
        val view = tabViews[index] ?: buildTab(index).also {
            tabViews[index] = it
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
        }
        for (i in tabViews.indices) tabViews[i]?.visibility = if (i == index) View.VISIBLE else View.GONE
        if (animate) Motion.fadeUp(view)
    }

    private fun buildTab(index: Int): View = when (index) {
        0 -> HomeView(this)
        1 -> GroupedMessagesView(
            this,
            callReady = callReady,
            preview = preview,
            onConversationClick = { conversation ->
                if (preview) {
                    toast(DemoText.get(R.string.demo_preview_mode_not_logged_in_cannot_open_2), SocialToast.Kind.WARNING)
                } else {
                    startActivity(Intent(this, ChatActivity::class.java)
                        .putExtra("conversationId", conversation.conversationID)
                        .putExtra("peerName", conversation.title.orEmpty())
                        .putExtra("callReady", callReady))
                }
            },
            onContactClick = { userId ->
                if (preview) toast(DemoText.get(R.string.demo_preview_mode_not_logged_in_cannot_open_2), SocialToast.Kind.WARNING) else openChat(userId)
            },
            onSearchClick = {
                startActivity(Intent(this, SearchActivity::class.java).putExtra("callReady", callReady))
            },
            onCallBack = { peer, video -> if (callReady) call(peer, video) else callUnavailable() }
        ).also { view ->
            messagesView = view
            intent.getIntExtra("segment", -1).takeIf { it >= 0 }?.let { view.selectSegment(it) }
        }
        else -> mineView()
    }

    /** The profile changed: the Mine page is rebuilt (now if it is showing, otherwise when it is next opened). */
    private fun rebuildMine() {
        tabViews[2]?.let { content.removeView(it) }
        tabViews[2] = null
        if (current == 2) show(2)
    }

    /**
     * Real nickname / avatar / signature come from the IM profile (`LoginStore`, the same source the edit page writes
     * to), never from a fixture. A change made on the edit page refreshes the Mine tab straight away.
     */
    private fun loadSelfProfile() {
        profileScope?.cancel()
        profileScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main + kotlinx.coroutines.SupervisorJob()).also { scope ->
            scope.launch {
                io.trtc.tuikit.atomicxcore.api.login.LoginStore.shared.loginState.loginUserInfo.collectLatest { info ->
                    info ?: return@collectLatest
                    nickname = info.nickname?.takeIf { it.isNotBlank() } ?: accountId
                    avatarURL = info.avatarURL
                    signature = info.selfSignature.orEmpty()
                    if (::content.isInitialized) rebuildMine()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        DemoMessageBanner.onShown = null
        profileScope?.cancel()
        profileScope = null
    }

    private fun mineView(): LinearLayout = LinearLayout(this).apply {
        val identity = if (preview) {
            MineIdentity(DemoText.get(R.string.demo_ye), accountId, "demo_avatar_me", "", DemoText.get(R.string.demo_id_7271_76_shenzhen))
        } else {
            MineIdentity(nickname, accountId, avatarURL, signature)
        }
        addView(MineView(this@MainActivity, identity), LinearLayout.LayoutParams(-1, -1))
    }

    private fun openChat(peer: String) {
        startActivity(Intent(this, ChatActivity::class.java)
            .putExtra("peerId", peer).putExtra("callReady", callReady))
    }

    private fun call(peer: String, video: Boolean = true) {
        AtomicCallEventPublisher.publishStartCall(
            listOf(peer),
            if (video) AtomicCallEventPublisher.MEDIA_TYPE_VIDEO else AtomicCallEventPublisher.MEDIA_TYPE_AUDIO
        )
    }

    private fun callUnavailable() {
        HostDiagnostics.record("host.call", 0, "call component not ready")
        toast(DemoText.get(BaseR.string.demo_call_sdk_is_not_ready_please_log), SocialToast.Kind.WARNING)
    }

    private fun toast(message: String, kind: SocialToast.Kind = SocialToast.Kind.DEFAULT) =
        SocialToast.show(this, message, kind, SocialToast.Duration.LONG)

    override fun onBackPressed() {
        if (current == 1 && messagesView?.handleBack() == true) return
        if (current != 0) show(0) else super.onBackPressed()
    }
}
