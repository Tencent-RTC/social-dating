package io.trtc.tuikit.chat.home

import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import io.trtc.tuikit.chat.home.data.HomeUserDetail
import io.trtc.tuikit.chat.home.ui.ProfileUi
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostHeader
import io.trtc.tuikit.chat.hostbase.HostStateView
import io.trtc.tuikit.chat.hostbase.HostThread
import io.trtc.tuikit.chat.hostbase.R as BaseR

class AlbumActivity : DemoActivity() {
    private val tokens get() = DemoUi.tokens
    private lateinit var page: LinearLayout
    private var userKey = ""
    private var alive = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        userKey = intent.getStringExtra(ProfileActivity.EXTRA_USER_KEY) ?: return finish()
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
    }

    private fun load() {
        page.removeAllViews()
        page.addView(HostHeader(this, DemoText.get(R.string.demo_album), left = backButton()))
        HomeKit.cachedDetail(userKey)?.let { return show(it) }
        val state = HostStateView.asContent(this)
        page.addView(FrameLayout(this).apply {
            setBackgroundColor(tokens.bgColorDefault)
            addView(state)
        }, LinearLayout.LayoutParams(-1, 0, 1f))
        state.showLoading()
        HomeKit.dataSource.loadUserDetail(userKey) { result ->
            HostThread.runOnMain {
                if (!alive) return@runOnMain
                result.onSuccess {
                    HomeKit.cacheDetail(userKey, it)
                    page.removeAllViews()
                    page.addView(HostHeader(this, DemoText.get(R.string.demo_album), left = backButton()))
                    show(it)
                }.onFailure { state.showError { load() } }
            }
        }
    }

    private fun backButton() = Host.backButton(this) { finish() }

    private fun show(detail: HomeUserDetail) {
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        body.addView(grid(detail))
        page.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            setBackgroundColor(tokens.bgColorDefault)
            addView(body)
        }, LinearLayout.LayoutParams(-1, 0, 1f))
    }

    private fun grid(data: HomeUserDetail) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        val gap = Host.dp(this@AlbumActivity, 2)
        data.albumPhotos.chunked(3).forEachIndexed { row, names ->
            addView(LinearLayout(this@AlbumActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                names.forEachIndexed { column, name ->
                    val video = row * 3 + column == data.albumPhotos.lastIndex && data.albumPhotos.size > 3
                    addView(ProfileUi.thumb(this@AlbumActivity, name, 0f, if (video) 32 else 0).apply {
                        contentDescription = DemoText.get(R.string.demo_photo)
                        setOnClickListener { HomeKit.actions.onAlbumPhotoClick(this@AlbumActivity, data.card, name) }
                    }, LinearLayout.LayoutParams(0, Host.dp(this@AlbumActivity, 118), 1f).apply {
                        if (column > 0) marginStart = gap
                    })
                }
                repeat(3 - names.size) { addView(View(this@AlbumActivity), LinearLayout.LayoutParams(0, 1, 1f)) }
            }, LinearLayout.LayoutParams(-1, -2).apply { if (row > 0) topMargin = gap })
        }
    }
}
