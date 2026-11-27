package io.trtc.tuikit.chat.home.ui

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.LayerDrawable
import android.view.animation.LinearInterpolator
import io.trtc.tuikit.chat.hostbase.Motion
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.trtc.tuikit.chat.home.HomeKit
import io.trtc.tuikit.chat.home.R
import io.trtc.tuikit.chat.home.data.HomeProfilePost
import io.trtc.tuikit.chat.home.data.HomeUserCard
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.HostPhoto
import io.trtc.tuikit.chat.hostbase.TagKind
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.hostbase.sampleAvatar
import android.graphics.PorterDuff
import android.widget.ImageView

/**
 * Shared pieces of the other-person profile (design B5 `527:2357`) and its album / posts sub page
 * (B6). Pure view builders: all data is passed in by the caller, no IM or data source access.
 */
object ProfileUi {
    private val tokens get() = DemoUi.tokens

    fun photo(context: Context, ref: String?, radiusDp: Float = 0f): FrameLayout = HostPhoto.tile(context, ref, radiusDp)

    /** `.playbadge`: black 45% disc with a white play glyph. */
    fun playBadge(context: Context, diameterDp: Int): View = FrameLayout(context).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(0x73000000) }
        addView(Host.icon(context, R.drawable.demo_ic_play, diameterDp / 2, 0xFFFFFFFF.toInt()),
            FrameLayout.LayoutParams(Host.dp(context, diameterDp / 2), Host.dp(context, diameterDp / 2), Gravity.CENTER))
    }

    /** `.thumb`: photo tile with an optional centred play badge. */
    fun thumb(context: Context, name: String, radiusDp: Float, videoBadgeDp: Int = 0): View = photo(context, name, radiusDp).apply {
        if (videoBadgeDp > 0) {
            addView(playBadge(context, videoBadgeDp), FrameLayout.LayoutParams(Host.dp(context, videoBadgeDp),
                Host.dp(context, videoBadgeDp), Gravity.CENTER))
        }
    }

    /** `.blockhead`: bold 16 title + count (em, bold, 8dp gap) and a 12sp 「全部」 link. */
    fun blockHead(context: Context, title: String, count: Int, onAll: (() -> Unit)?): View = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(Host.text(context, title, 16f, tokens.textColorPrimary, bold = true))
        addView(Host.text(context, count.toString(), 16f, tokens.textColorPrimary, bold = true),
            LinearLayout.LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 8) })
        addView(View(context), LinearLayout.LayoutParams(0, 1, 1f))
        if (onAll != null) addView(Host.text(context, DemoText.get(R.string.demo_all), 12f, tokens.textColorSecondary).apply {
            contentDescription = DemoText.get(R.string.demo_view_all, title)
            setOnClickListener { onAll() }
        })
    }

    /** `.itag`: h26 r13, level colour at 16% fill with the level colour as ink. */
    fun interestTag(context: Context, text: String, level: Int): View {
        val color = when (level) {
            1 -> tokens.tagColorLevel1
            2 -> tokens.tagColorLevel2
            3 -> tokens.tagColorLevel3
            else -> tokens.tagColorLevel4
        }
        return Host.text(context, text, 12f, color).apply {
            gravity = Gravity.CENTER
            setPadding(Host.dp(context, 10), 0, Host.dp(context, 10), 0)
            background = Host.rounded(context, Host.alpha(color, 0.16f), 13f)
        }
    }

    /** `.sextag--solid` textual (B5): 「女 23」, h20 r10, the gender's age token (male blue / female pink) at 92%, bold 11. */
    fun solidSexTag(context: Context, sex: String, age: Int): View =
        Host.text(context, "${DemoText.get(if (sex == "m") R.string.demo_male else R.string.demo_female)} $age", 11f, tokens.textColorButton, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(Host.dp(context, 8), 0, Host.dp(context, 8), 0)
            background = Host.rounded(context, Host.alpha(Host.tagAccent(Host.ageKind(sex)), 0.92f), 10f)
        }

    /**
     * `.ident__voice`: h36 pill, four-bar glyph and 「听听我的声音  8s」 in the link colour.
     * Tap plays a silent preview: the bars bounce, a link-tinted fill sweeps the pill left to right over [seconds]
     * and the label counts down; tapping again (or the end) resets it. [onPlay] runs when a preview starts, where a
     * host can later start the audio.
     */
    fun voiceButton(context: Context, seconds: Int, onPlay: () -> Unit = {}): View {
        val c = tokens
        val fill = ClipDrawable(Host.rounded(context, Host.alpha(c.textColorLink, 0.18f), 18f), Gravity.START, ClipDrawable.HORIZONTAL)
        val bars = ArrayList<View>()
        val label = Host.text(context, DemoText.get(R.string.demo_listen_to_my_voice_s, seconds), 12f, c.textColorLink)
        var running: AnimatorSet? = null
        var sweep: ValueAnimator? = null

        fun reset() {
            // Clear the fields first: cancel() fires onAnimationEnd, which must not re-enter reset().
            val bounce = running
            val progress = sweep
            running = null
            sweep = null
            bounce?.cancel()
            progress?.cancel()
            bars.forEach { it.scaleY = 1f }
            fill.level = 0
            label.text = DemoText.get(R.string.demo_listen_to_my_voice_s, seconds)
        }

        val pill = object : LinearLayout(context) {
            override fun onDetachedFromWindow() {
                reset()
                super.onDetachedFromWindow()
            }
        }
        return pill.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = LayerDrawable(arrayOf(Host.rounded(context, c.bgColorFunction, 18f), fill))
            setPadding(Host.dp(context, 12), 0, Host.dp(context, 14), 0)
            contentDescription = DemoText.get(R.string.demo_voice_signature)
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(Host.dp(context, 2), 0, Host.dp(context, 2), 0)
                listOf(4, 9, 6, 8).forEachIndexed { index, h ->
                    val bar = View(context).apply { background = Host.rounded(context, c.textColorLink, 1f) }
                    bars += bar
                    addView(bar, LinearLayout.LayoutParams(Host.dp(context, 2), Host.dp(context, h)).apply {
                        if (index > 0) marginStart = Host.dp(context, 1)
                    })
                }
            }, LinearLayout.LayoutParams(Host.dp(context, 16), Host.dp(context, 16)))
            addView(label, LinearLayout.LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 8) })
            setOnClickListener {
                if (running != null || sweep != null) return@setOnClickListener reset()
                onPlay()
                val animated = Motion.enabled(context)
                var shown = seconds
                sweep = ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = seconds * 1000L
                    interpolator = LinearInterpolator()
                    addUpdateListener {
                        val fraction = it.animatedValue as Float
                        if (animated) fill.level = (fraction * 10000).toInt()
                        val left = kotlin.math.ceil(seconds * (1f - fraction)).toInt().coerceAtLeast(0)
                        if (left != shown) {
                            shown = left
                            label.text = DemoText.get(R.string.demo_listen_to_my_voice_s, left)
                        }
                    }
                    addListener(object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            if (sweep === animation) reset()
                        }
                    })
                    start()
                }
                if (animated) {
                    running = AnimatorSet().apply {
                        playTogether(bars.mapIndexed { index, bar ->
                            ObjectAnimator.ofFloat(bar, View.SCALE_Y, 0.5f, 1.7f).apply {
                                duration = 320L + index * 70L
                                repeatCount = ValueAnimator.INFINITE
                                repeatMode = ValueAnimator.REVERSE
                                startDelay = index * 90L
                                interpolator = Motion.easeInOut
                            }
                        })
                        start()
                    }
                }
            }
        }
    }

    /** `.post`: avatar 40 + name / 实名 / sub, text, 172dp photo, topic pill, like / comment. */
    fun postCard(context: Context, card: HomeUserCard, post: HomeProfilePost): View {
        val c = tokens
        var liked = false
        var likes = post.likes
        val likeIcon = Host.icon(context, R.drawable.demo_ic_like, 15, Host.alpha(c.textColorPrimary, 0.4f))
        val likeCount = Host.text(context, likes.toString(), 12f, c.textColorTertiary)
        val like = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            contentDescription = DemoText.get(R.string.demo_like)
            addView(likeIcon, LinearLayout.LayoutParams(Host.dp(context, 15), Host.dp(context, 15)))
            addView(likeCount, LinearLayout.LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 5) })
            setOnClickListener {
                liked = !liked
                likes += if (liked) 1 else -1
                likeCount.text = likes.toString()
                likeCount.setTextColor(if (liked) c.tagColorLevel4 else c.textColorTertiary)
                likeIcon.setImageResource(if (liked) R.drawable.demo_ic_like_on else R.drawable.demo_ic_like)
                likeIcon.setColorFilter(if (liked) c.tagColorLevel4 else Host.alpha(c.textColorPrimary, 0.4f))
            }
        }
        val comment = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            contentDescription = DemoText.get(R.string.demo_comment)
            addView(Host.icon(context, R.drawable.demo_ic_comment, 15, Host.alpha(c.textColorPrimary, 0.4f)),
                LinearLayout.LayoutParams(Host.dp(context, 15), Host.dp(context, 15)))
            addView(Host.text(context, post.comments.toString(), 12f, c.textColorTertiary),
                LinearLayout.LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 5) })
            setOnClickListener { HomeKit.actions.onCommentClick(context, card, post) }
        }
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = Host.rounded(context, c.bgColorOperate, HostMetrics.CARD_RADIUS.toFloat())
            setPadding(Host.dp(context, 12), Host.dp(context, 12), Host.dp(context, 12), Host.dp(context, 12))
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(sampleAvatar(context, card.avatar, card.displayName, 40))
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(LinearLayout(context).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        addView(Host.text(context, card.displayName, 14f, c.textColorPrimary, bold = true))
                        addView(Host.verifiedTag(context, DemoText.get(BaseR.string.demo_verified)), LinearLayout.LayoutParams(-2, Host.dp(context, 18)).apply {
                            marginStart = Host.dp(context, 5)
                        })
                    })
                    addView(Host.text(context, post.sub, 11f, c.textColorTertiary),
                        LinearLayout.LayoutParams(-2, -2).apply { topMargin = Host.dp(context, 3) })
                }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = Host.dp(context, 10) })
            })
            addView(Host.text(context, post.text, 14f, c.textColorPrimary).apply { setLineSpacing(Host.dpf(context, 7f), 1f) },
                LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(context, 10) })
            post.photos.firstOrNull()?.let {
                addView(photo(context, it, 10f), LinearLayout.LayoutParams(-1, Host.dp(context, 172)).apply {
                    topMargin = Host.dp(context, 10)
                })
            }
            if (post.topic.isNotBlank()) {
                val ink = if (DemoUi.isDark) androidx.core.graphics.ColorUtils.blendARGB(c.tagColorLevel3, 0xFFFFFFFF.toInt(), 0.25f)
                else c.tagColorLevel3
                addView(Host.text(context, post.topic, 11f, ink).apply {
                    gravity = Gravity.CENTER
                    setPadding(Host.dp(context, 9), 0, Host.dp(context, 10), 0)
                    background = Host.rounded(context, Host.alpha(c.tagColorLevel3, 0.15f), 12f)
                }, LinearLayout.LayoutParams(-2, Host.dp(context, 24)).apply { topMargin = Host.dp(context, 10) })
            }
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(like)
                addView(comment, LinearLayout.LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 28) })
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(context, 12) })
        }
    }
}

/**
 * Profile header right action, icon only (Ardot board M, shortened): a 32dp disc inside a 36dp touch area.
 * Not a friend: brand gradient disc + person-with-plus; friend: quiet function disc + person with a green check.
 * Colours come from the semantic tokens, so every palette and light/dark mode follows.
 */
class FriendActionButton(context: Context) : FrameLayout(context) {
    private val disc = View(context)
    private val person = ImageView(context)
    private val badge = ImageView(context)
    private var shownFriend: Boolean? = null

    init {
        layoutParams = android.widget.LinearLayout.LayoutParams(Host.dp(context, TOUCH_DP), Host.dp(context, TOUCH_DP))
        isClickable = true
        isFocusable = true
        addView(disc, LayoutParams(Host.dp(context, DISC_DP), Host.dp(context, DISC_DP), Gravity.CENTER))
        for (icon in listOf(person, badge)) {
            icon.scaleType = ImageView.ScaleType.FIT_CENTER
            icon.isClickable = false
            addView(icon, LayoutParams(Host.dp(context, ICON_DP), Host.dp(context, ICON_DP), Gravity.CENTER))
        }
        person.setImageResource(R.drawable.demo_ic_friend_person)
    }

    /** Shows the add / friend state; [animate] plays the short pop used when the state flips after a tap. */
    fun render(friend: Boolean, animate: Boolean = false) {
        val changed = shownFriend != null && shownFriend != friend
        shownFriend = friend
        val tokens = DemoUi.tokens
        contentDescription = DemoText.get(if (friend) R.string.demo_already_friends else R.string.demo_add_friend)
        if (friend) {
            disc.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(tokens.bgColorFunction)
            }
            person.setColorFilter(tokens.textColorSecondary, PorterDuff.Mode.SRC_IN)
            badge.setImageResource(R.drawable.demo_ic_friend_check)
            badge.setColorFilter(tokens.textColorSuccess, PorterDuff.Mode.SRC_IN)
        } else {
            disc.background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(tokens.buttonColorPrimaryDefault, tokens.tagColorLevel4)
            ).apply { shape = GradientDrawable.OVAL }
            person.setColorFilter(tokens.textColorButton, PorterDuff.Mode.SRC_IN)
            badge.setImageResource(R.drawable.demo_ic_friend_plus)
            badge.setColorFilter(tokens.textColorButton, PorterDuff.Mode.SRC_IN)
        }
        if (animate && changed && Motion.enabled(context)) pop()
    }

    private fun pop() {
        animate().cancel()
        scaleX = 0.92f
        scaleY = 0.92f
        animate().scaleX(1f).scaleY(1f).setDuration(160).setInterpolator(Motion.spring).start()
        badge.animate().cancel()
        badge.scaleX = 0.8f
        badge.scaleY = 0.8f
        badge.animate().scaleX(1f).scaleY(1f).setDuration(220).setInterpolator(Motion.spring).start()
    }

    private companion object {
        const val TOUCH_DP = 36
        const val DISC_DP = 32
        const val ICON_DP = 18
    }
}
