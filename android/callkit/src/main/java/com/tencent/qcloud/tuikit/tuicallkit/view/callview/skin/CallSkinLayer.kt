package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.tencent.qcloud.tuikit.tuicallkit.R
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.message.CustomMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.MessageEvent
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import io.trtc.tuikit.atomicxcore.api.message.MessageListStore
import io.trtc.tuikit.atomicxcore.api.message.MessageLoadOption
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** S9 background: dark scrim over the blurred peer avatar + a palette-coloured glow behind the avatar. */
class VoiceShadeView(context: Context, private val t: ColorTokens) : View(context) {
    private val scrim = Paint()
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        val bg = t.bgColorDefault
        scrim.shader = LinearGradient(
            0f, 0f, 0f, h.toFloat(),
            intArrayOf(CallSkin.withAlpha(bg, 0.35f), CallSkin.withAlpha(bg, 0.60f), CallSkin.withAlpha(bg, 0.94f)),
            floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP
        )
        // Design `.callglow`: 440x360 box at (-40,108), radial primary colour at 50% opacity.
        val scale = w / 360f
        val cx = w / 2f
        val cy = (108f + 180f) * scale
        val radial = RadialGradient(
            0f, 0f, 1f,
            intArrayOf(CallSkin.withAlpha(t.buttonColorPrimaryDefault, 0.5f), Color.TRANSPARENT),
            floatArrayOf(0f, 1f), Shader.TileMode.CLAMP
        )
        radial.setLocalMatrix(Matrix().apply { setScale(220f * scale, 180f * scale); postTranslate(cx, cy) })
        glow.shader = radial
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), scrim)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glow)
    }
}

/**
 * S10 shades: soft black gradients over the remote picture, drawn *under* the control buttons.
 * Kept light on purpose: the first version (0.55 top / 0.92 bottom, over the controls too) made the picture
 * look dim and the buttons look covered. The round buttons carry their own translucent fill for legibility.
 */
class VideoShadeView(context: Context) : View(context) {
    private val top = Paint()
    private val bottom = Paint()
    private var topH = 0f

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        topH = 180f * resources.displayMetrics.density
        top.shader = LinearGradient(0f, 0f, 0f, topH, Color.argb(90, 0, 0, 0), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        val start = h * 0.58f
        bottom.shader = LinearGradient(
            0f, start, 0f, h.toFloat(),
            intArrayOf(Color.TRANSPARENT, Color.argb(70, 0, 0, 0), Color.argb(120, 0, 0, 0), Color.argb(150, 0, 0, 0)),
            floatArrayOf(0f, 0.35f, 0.7f, 1f), Shader.TileMode.CLAMP
        )
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, width.toFloat(), topH, top)
        canvas.drawRect(0f, height * 0.58f, width.toFloat(), height.toFloat(), bottom)
    }
}

/**
 * Overlay above the SDK call picture: peer name, voice-page safety tip, video topic popup, and the
 * gift banner / flying hearts (own gifts and gifts received from the peer as custom messages).
 * It never intercepts touches.
 */
class CallSkinLayer(
    context: Context,
    private val hub: CallSkinHub,
    private val video: Boolean,
    private val topInset: Int
) : FrameLayout(context) {
    private val t = CallSkin.tokens(context)
    private val nameView: TextView
    private var topicCard: LinearLayout? = null
    private var topicTitle: TextView? = null
    private var topicBody: TextView? = null
    private var banner: LinearLayout? = null
    private var bannerCombo: TextView? = null
    private var bannerAvatar: TextView? = null
    private var bannerAvatarImage: android.widget.ImageView? = null
    private var bannerWho: TextView? = null
    private var bannerWhat: TextView? = null
    private var peerName = ""
    private var peerJob: Job? = null
    private var attachedAtMs = 0L
    private val hearts = listOf(t.tagColorLevel4, t.buttonColorPrimaryDefault, t.tagColorLevel4, t.textColorWarning, t.buttonColorPrimaryDefault)
    private var nextHeart = 0

    private val topicListener: () -> Unit = { renderTopic() }
    private val giftListener: (Int) -> Unit = { combo -> showGift(combo, false, hub.giftName) }
    private val peerGiftListener: (String, Int) -> Unit = { name, combo -> showGift(combo, true, name.ifBlank { hub.giftName }) }

    init {
        isClickable = false
        isFocusable = false
        nameView = CallSkin.text(context, "", 16f, t.textColorPrimary, bold = true).apply {
            gravity = Gravity.CENTER
            setShadowLayer(CallSkin.dp(context, 2f).toFloat(), 0f, 1f, Color.argb(90, 0, 0, 0))
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        addView(nameView, LayoutParams(-2, -2, Gravity.CENTER_HORIZONTAL or Gravity.TOP).apply {
            topMargin = topInset + CallSkin.dp(context, 4f)
            marginStart = CallSkin.dp(context, 64f)
            marginEnd = CallSkin.dp(context, 64f)
        })
        if (!video) hub.showTopic(true)
        addView(topicCardView(), if (video) {
            LayoutParams(CallSkin.dp(context, 220f), -2, Gravity.TOP or Gravity.START).apply {
                topMargin = topInset + CallSkin.dp(context, 56f)
                marginStart = CallSkin.dp(context, 16f)
            }
        } else {
            LayoutParams(CallSkin.dp(context, 288f), -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                bottomMargin = CallSkin.dp(context, 270f)
            }
        })
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        attachedAtMs = System.currentTimeMillis()
        hub.addTopicListener(topicListener)
        hub.addGiftListener(giftListener)
        hub.addPeerGiftListener(peerGiftListener)
        renderTopic()
        listenPeerGifts()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        hub.removeTopicListener(topicListener)
        hub.removeGiftListener(giftListener)
        hub.removePeerGiftListener(peerGiftListener)
        peerJob?.cancel()
        peerJob = null
    }

    fun setPeerName(name: String) {
        peerName = name
        nameView.text = name
    }

    private fun listenPeerGifts() {
        val inspector = CallGiftBridge.inspector ?: return
        peerJob?.cancel()
        peerJob = CoroutineScope(Dispatchers.Main).launch {
            runCatching {
                val state = CallStore.shared.observerState
                state.allParticipants
                    .map { list -> list.firstOrNull { it.id != state.selfInfo.value.id }?.id }
                    .distinctUntilChanged()
                    .collectLatest { peer ->
                        if (peer.isNullOrBlank()) return@collectLatest
                        val store = MessageListStore.create("c2c_$peer")
                        store.loadMessages(MessageLoadOption(pageCount = 1))
                        val seen = HashSet<String>()
                        launch {
                            store.messageEventFlow.collect { event ->
                                if (event is MessageEvent.OnReceiveNewMessage) consumePeerMessage(event.message, seen, inspector)
                            }
                        }
                        store.state.messageList.collect { list -> list.forEach { consumePeerMessage(it, seen, inspector) } }
                    }
            }
        }
    }

    private fun consumePeerMessage(message: MessageInfo, seen: MutableSet<String>, inspector: (String?) -> String?) {
        if (message.isSentBySelf) return
        val sentAtMs = (message.timestamp ?: 0L) * 1000L
        if (sentAtMs < attachedAtMs - 3000L || !seen.add(message.msgID)) return
        val data = (message.messagePayload as? CustomMessagePayload)?.customData
        inspector(data)?.let { hub.receivePeerGift(it) }
    }

    /** Distance from the layer bottom to where the video gift banner sits (design y=482 on 800). */
    private fun bannerBottomMargin() = CallSkin.dp(context, 274f)

    private fun topicCardView(): View {
        val pad = if (video) 12f else 14f
        val card = DraggableCard(context, topInset).apply {
            orientation = LinearLayout.VERTICAL
            background = CallSkin.rounded(context, t.bgColorTagMask, 16f)
            setPadding(CallSkin.dp(context, pad), CallSkin.dp(context, pad - 2f), CallSkin.dp(context, pad), CallSkin.dp(context, pad))
            visibility = View.GONE
        }
        val head = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        head.addView(CallSkin.icon(context, R.drawable.callskin_ic_bulb, 14f, t.textColorWarning))
        val title = CallSkin.text(context, hub.topicTitle, 12f, t.textColorWarning, bold = true).apply {
            maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
        }
        head.addView(title, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = CallSkin.dp(context, 6f) })
        val next = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        next.addView(CallSkin.icon(context, R.drawable.callskin_ic_refresh, 12f, t.textColorSecondary))
        next.addView(
            CallSkin.text(context, context.getString(R.string.callskin_topic_next), 12f, t.textColorSecondary),
            LinearLayout.LayoutParams(-2, -2).apply { marginStart = CallSkin.dp(context, 4f) }
        )
        CallSkin.pressable(next, 0.95f) { hub.nextTopic() }
        head.addView(next)
        card.addView(head)
        val bodySize = if (video) 13f else 14f
        val lineDp = if (video) 19f else 21f
        val body = CallSkin.text(context, hub.topicText, bodySize, t.textColorPrimary).apply {
            setLineSpacing(CallSkin.dp(context, lineDp) - textSize, 1f)
        }
        card.addView(body, LinearLayout.LayoutParams(-1, -2).apply { topMargin = CallSkin.dp(context, 6f) })
        topicCard = card
        topicTitle = title
        topicBody = body
        return card
    }

    private fun renderTopic() {
        topicTitle?.text = hub.topicTitle
        topicBody?.text = hub.topicText
        val card = topicCard ?: return
        if (hub.topicVisible && card.visibility != View.VISIBLE) {
            card.visibility = View.VISIBLE
            card.alpha = 0f
            card.scaleX = 0.92f
            card.scaleY = 0.92f
            card.pivotX = 0f
            card.pivotY = 0f
            card.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(220).start()
        } else if (!hub.topicVisible && card.visibility == View.VISIBLE) {
            card.animate().alpha(0f).setDuration(160).withEndAction { card.visibility = View.GONE }.start()
        }
    }

    private fun showGift(combo: Int, fromPeer: Boolean, giftName: String) {
        if (video) {
            ensureBanner()
            val who = if (fromPeer) peerName.ifBlank { context.getString(R.string.callskin_gift_banner_peer) } else context.getString(R.string.callskin_gift_banner_me)
            bannerAvatar?.text = who.take(1)
            bindBannerAvatar(fromPeer)
            bannerWho?.text = who
            // A gift from the peer is addressed to this user: "<peer> sent you <gift>"; our own is "Me sent <gift>".
            bannerWhat?.text = context.getString(
                if (fromPeer) R.string.callskin_gift_banner_to_you else R.string.callskin_gift_banner_send, giftName
            )
            bannerCombo?.text = "×$combo"
            banner?.let { b ->
                b.animate().cancel()
                b.alpha = 1f
                b.translationX = 0f
                b.removeCallbacks(fadeBanner)
                b.postDelayed(fadeBanner, 3200)
            }
        }
        repeat(3) { flyHeart() }
    }

    private fun bindBannerAvatar(fromPeer: Boolean) {
        val image = bannerAvatarImage ?: return
        val state = runCatching { CallStore.shared.observerState }.getOrNull()
        val self = state?.selfInfo?.value
        val url = if (fromPeer) {
            state?.allParticipants?.value?.firstOrNull { it.id != self?.id }?.avatarURL
        } else {
            self?.avatarURL
        }
        if (url.isNullOrBlank()) {
            image.setImageDrawable(null)
            return
        }
        com.bumptech.glide.Glide.with(context.applicationContext).load(url).centerCrop().into(image)
    }

    private val fadeBanner = Runnable {
        banner?.animate()?.alpha(0f)?.setDuration(320)?.start()
    }

    private fun ensureBanner() {
        if (banner != null) return
        val bar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val gradient = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(
                    CallSkin.withAlpha(t.buttonColorPrimaryDefault, 0.85f),
                    CallSkin.withAlpha(t.tagColorLevel4, 0.85f),
                    Color.TRANSPARENT
                )
            ).apply { cornerRadius = CallSkin.dp(context, 22f).toFloat() }
            background = gradient
            setPadding(CallSkin.dp(context, 4f), CallSkin.dp(context, 4f), CallSkin.dp(context, 24f), CallSkin.dp(context, 4f))
        }
        val avatar = TextView(context).apply {
            text = context.getString(R.string.callskin_gift_banner_me)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(t.textColorButton)
            gravity = Gravity.CENTER
            background = CallSkin.oval(CallSkin.withAlpha(Color.BLACK, 0.28f))
        }
        val avatarImage = android.widget.ImageView(context).apply { scaleType = android.widget.ImageView.ScaleType.CENTER_CROP }
        val avatarBox = FrameLayout(context).apply {
            clipToOutline = true
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) = outline.setOval(0, 0, view.width, view.height)
            }
            addView(avatar, LayoutParams(-1, -1))
            addView(avatarImage, LayoutParams(-1, -1))
        }
        bannerAvatarImage = avatarImage
        bar.addView(avatarBox, LinearLayout.LayoutParams(CallSkin.dp(context, 36f), CallSkin.dp(context, 36f)))
        val who = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val whoText = CallSkin.text(context, context.getString(R.string.callskin_gift_banner_me), 12f, t.textColorPrimary, bold = true)
        val whatText = CallSkin.text(context, context.getString(R.string.callskin_gift_banner_send, hub.giftName), 12f, t.textColorSecondary)
        who.addView(whoText)
        who.addView(whatText)
        bannerAvatar = avatar
        bannerWho = whoText
        bannerWhat = whatText
        bar.addView(who, LinearLayout.LayoutParams(-2, -2).apply { marginStart = CallSkin.dp(context, 8f) })
        bar.addView(
            CallSkin.icon(context, R.drawable.callskin_ic_gift_candy, 36f),
            LinearLayout.LayoutParams(CallSkin.dp(context, 36f), CallSkin.dp(context, 36f)).apply { marginStart = CallSkin.dp(context, 8f) }
        )
        val combo = CallSkin.text(context, "×1", 22f, t.textColorWarning, bold = true).apply {
            setShadowLayer(CallSkin.dp(context, 2f).toFloat(), 0f, CallSkin.dp(context, 2f).toFloat(), Color.argb(150, 255, 112, 46))
        }
        bar.addView(combo, LinearLayout.LayoutParams(-2, -2).apply { marginStart = CallSkin.dp(context, 8f) })
        banner = bar
        bannerCombo = combo
        addView(bar, LayoutParams(-2, CallSkin.dp(context, 44f), Gravity.START or Gravity.BOTTOM).apply {
            marginStart = CallSkin.dp(context, 12f)
            bottomMargin = bannerBottomMargin()
        })
    }

    private fun flyHeart() {
        val size = CallSkin.dp(context, (14 + (nextHeart % 3) * 7).toFloat())
        val color = hearts[nextHeart % hearts.size]
        nextHeart += 1
        val heart = CallSkin.icon(context, R.drawable.callskin_ic_heart, 28f, color)
        addView(heart, LayoutParams(size, size, Gravity.END or Gravity.BOTTOM).apply {
            marginEnd = CallSkin.dp(context, (22 + (nextHeart * 17) % 44).toFloat())
            bottomMargin = CallSkin.dp(context, 250f)
        })
        val rise = ObjectAnimator.ofFloat(heart, TRANSLATION_Y, 0f, -CallSkin.dp(context, 190f + nextHeart * 9f).toFloat())
        val fade = ObjectAnimator.ofFloat(heart, ALPHA, 1f, 0f)
        rise.interpolator = DecelerateInterpolator()
        rise.duration = 1800
        fade.duration = 1800
        fade.startDelay = 700
        rise.startDelay = (nextHeart % 3) * 120L
        fade.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                removeView(heart)
            }
        })
        rise.start()
        fade.start()
    }
}
