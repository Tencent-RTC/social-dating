package io.trtc.tuikit.chat.demo.chat

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.atomicxcore.api.message.CustomMessagePayload
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.social.DemoCardLocalState
import io.trtc.tuikit.chat.demo.social.DemoCardProtocol
import io.trtc.tuikit.chat.demo.social.DemoEffectGate
import io.trtc.tuikit.chat.demo.social.DemoInteractionState
import io.trtc.tuikit.chat.demo.social.DemoInteractionStore
import io.trtc.tuikit.chat.demo.social.DemoRps
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostPhoto
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageContentRenderer
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderConfig
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderContext
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageSummaryProvider
import java.util.UUID
import java.util.WeakHashMap

/**
 * Renders chat.card messages. [onReplay] is the only way out of the renderer: a received card
 * that invites "play again" asks the chat screen, which owns sending, to start the next round.
 */
class DemoCardRenderer(private val onReplay: (kind: String) -> Unit = {}) : MessageContentRenderer {
    override val renderConfig = MessageRenderConfig(useDefaultBubble = false)

    private val tickers = WeakHashMap<View, Runnable>()


    override fun createView(context: Context, parent: ViewGroup): View = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = ViewGroup.LayoutParams(DemoUi.dp(context, 232), ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    class Env(val conversationId: String, val rebind: () -> Unit)

    override fun bindView(view: View, context: MessageRenderContext) {
        val root = view as LinearLayout
        val data = (context.message.messagePayload as? CustomMessagePayload)?.customData
        val timeMs = context.message.timestamp?.times(1000) ?: System.currentTimeMillis()
        render(root, context.message.isSentBySelf, data, timeMs, Env(context.conversationID) { bindView(root, context) })
    }

    fun render(root: LinearLayout, self: Boolean, data: String?, messageTimeMs: Long, env: Env) {
        val ctx = root.context
        tickers.remove(root)?.let { root.removeCallbacks(it) }
        root.removeAllViews()
        root.gravity = Gravity.START
        root.setOnClickListener(null)
        root.isClickable = false
        root.clipToOutline = false
        root.outlineProvider = ViewOutlineProvider.BACKGROUND
        val card = DemoCardProtocol.parse(data)
        var effectTarget: View? = null
        when {
            card == null || !card.isKnownKind -> unsupported(root)
            card.kind == "pat" -> { effectTarget = pat(root, self, card) }
            card.kind == "listen" -> listen(root, self, card, env)
            card.kind == "photoSwap" -> photoSwap(root, self, card, env)
            card.kind == "location" -> { location(root, card) }
            card.kind == "burn" -> burn(root, self, card, env)
            card.kind == "dice" -> { effectTarget = dice(root, self, card) }
            card.kind == "rps" -> { effectTarget = rps(root, self, card) }
            card.kind == "quiz" -> quiz(root, card, env)
            card.kind == "gift" -> { effectTarget = gift(root, self, card) }
            card.kind == "redpacket" -> redPacket(root, self, card, env)
        }
        if (card != null && effectTarget != null && DemoEffectGate.shouldPlay(card.eventId, messageTimeMs)) {
            val target = effectTarget
            target.post { playEffect(card.kind, target) }
        }
    }

    private fun frame(root: LinearLayout, widthDp: Int, top: Int, side: Int, bottom: Int, background: GradientDrawable) {
        val ctx = root.context
        root.layoutParams = (root.layoutParams ?: ViewGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT)).apply {
            width = DemoUi.dp(ctx, widthDp)
        }
        root.setPadding(DemoUi.dp(ctx, side), DemoUi.dp(ctx, top), DemoUi.dp(ctx, side), DemoUi.dp(ctx, bottom))
        root.background = background
    }

    private fun fill(
        ctx: Context, radius: Int, start: Int, end: Int, stroke: Int? = null,
        orientation: GradientDrawable.Orientation = GradientDrawable.Orientation.TL_BR
    ) = GradientDrawable(orientation, intArrayOn(start, end)).apply {
        cornerRadius = DemoUi.dp(ctx, radius).toFloat()
        if (stroke != null) setStroke(DemoUi.dp(ctx, 1), stroke)
    }

    private fun intArrayOn(vararg values: Int) = values

    private fun tokens() = DemoUi.tokens

    private fun mix(from: Int, to: Int, fraction: Float) = androidx.core.graphics.ColorUtils.blendARGB(from, to, fraction)

    /** Tinted card surface: the dialog surface with [accent] mixed in at the start edge, a thin accent ring around it. */
    private fun tinted(ctx: Context, radius: Int, accent: Int, strength: Float = 0.2f, ring: Float = 0.24f,
                       orientation: GradientDrawable.Orientation = GradientDrawable.Orientation.LEFT_RIGHT): GradientDrawable {
        val surface = tokens().bgColorDialog
        return fill(ctx, radius, mix(surface, accent, strength), surface, Host.alpha(accent, ring), orientation)
    }

    private fun brandFill(ctx: Context, radius: Int): GradientDrawable =
        fill(ctx, radius, tokens().buttonColorPrimaryDefault, tokens().tagColorLevel4)

    private fun solid(ctx: Context, radius: Int, color: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = DemoUi.dp(ctx, radius).toFloat()
        if (stroke != null) setStroke(DemoUi.dp(ctx, 1), stroke)
    }

    private fun glyph(ctx: Context, res: Int, sizeDp: Int, tint: Int?) = ImageView(ctx).apply {
        setImageResource(res)
        scaleType = ImageView.ScaleType.FIT_CENTER
        if (tint != null) setColorFilter(tint)
        layoutParams = LinearLayout.LayoutParams(DemoUi.dp(ctx, sizeDp), DemoUi.dp(ctx, sizeDp))
    }

    private fun centeredGlyph(ctx: Context, res: Int, sizeDp: Int, tint: Int?) = glyph(ctx, res, sizeDp, tint).apply {
        layoutParams = FrameLayout.LayoutParams(DemoUi.dp(ctx, sizeDp), DemoUi.dp(ctx, sizeDp), Gravity.CENTER)
    }

    private fun photoName(ref: String?, fallback: String): String = when (ref) {
        "burn_sample_city" -> "demo_photo_chengdu"
        "swap_sample_city" -> "demo_photo_coffee"
        "swap_sample_peer" -> "demo_photo_sea"
        else -> fallback
    }

    private fun pat(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card): View {
        val ctx = root.context
        frame(root, 200, 6, 14, 6, tinted(ctx, 16, tokens().textColorWarning, 0.2f, 0.3f))
        val hand = ImageView(ctx).apply {
            setImageResource(R.drawable.demo_pat_hand)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        val label = if (self) DemoText.get(R.string.demo_you_patted_their_head) else card.payload["text"] ?: DemoText.get(R.string.demo_patted_your_head)
        root.addView(LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(hand, LinearLayout.LayoutParams(DemoUi.dp(ctx, 52), DemoUi.dp(ctx, 52)))
            addView(Host.text(ctx, label, 13f, tokens().textColorWarning, bold = true).apply {
                maxLines = 1
                setPadding(DemoUi.dp(ctx, 8), 0, DemoUi.dp(ctx, 2), 0)
            })
        })
        return hand
    }

    private fun listen(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card, env: Env) {
        val ctx = root.context
        frame(root, 232, 10, 10, 10, tinted(ctx, 14, tokens().buttonColorPrimaryDefault))
        val duration = card.payload["durationMs"]?.toLongOrNull() ?: 0L
        val view = DemoCardLocalState.listen(card.instanceId, duration, System.currentTimeMillis())
        val cover = FrameLayout(ctx).apply {
            addView(ImageView(ctx).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                setImageResource(Host.resId(ctx, "demo_photo_records"))
            }, FrameLayout.LayoutParams(-1, -1))
            Host.roundedClip(this, 10f)
        }
        val title = card.payload["title"]
        val invite = if (!title.isNullOrEmpty()) {
            if (self) DemoText.get(R.string.demo_you_invited_them_to_listen_song, title) else DemoText.get(R.string.demo_invited_you_to_listen_song, title)
        } else {
            if (self) DemoText.get(R.string.demo_you_invited_them_to_listen_together) else DemoText.get(R.string.demo_invited_you_to_listen_together)
        }
        val status = when {
            !view.joined -> DemoText.get(R.string.demo_tap_to_listen_together)
            view.playing -> DemoText.get(R.string.demo_listening_together, clock(view.positionMs))
            else -> DemoText.get(R.string.demo_listening_together_paused)
        }
        val progress = if (duration > 0) (view.positionMs.toFloat() / duration).coerceIn(0f, 1f) else 0f
        val track = LinearLayout(ctx).apply {
            background = solid(ctx, 2, tokens().strokeColorPrimary)
            addView(View(ctx).apply { background = solid(ctx, 2, tokens().buttonColorPrimaryDefault) },
                LinearLayout.LayoutParams(0, -1, progress.coerceAtLeast(0.001f)))
            addView(View(ctx), LinearLayout.LayoutParams(0, -1, (1f - progress).coerceAtLeast(0.001f)))
        }
        val meta = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(DemoUi.dp(ctx, 10), 0, DemoUi.dp(ctx, 10), 0)
            addView(Host.text(ctx, invite, 13f, tokens().textColorPrimary, bold = true).apply {
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            })
            addView(Host.text(ctx, status, 10f, tokens().textColorTertiary).apply {
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                setPadding(0, DemoUi.dp(ctx, 5), 0, DemoUi.dp(ctx, 5))
            })
            addView(track, LinearLayout.LayoutParams(-1, DemoUi.dp(ctx, 3)))
        }
        val button = FrameLayout(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Host.alpha(tokens().buttonColorPrimaryDefault, 0.2f)) }
            contentDescription = if (view.playing) DemoText.get(R.string.demo_pause_listening_together) else DemoText.get(R.string.demo_listen_together)
            addView(centeredGlyph(ctx, if (view.playing) R.drawable.demo_ic_pause else R.drawable.demo_ic_note, 15, tokens().buttonColorPrimaryDefault))
            setOnClickListener {
                DemoCardLocalState.toggleListen(card.instanceId, duration, System.currentTimeMillis())
                env.rebind()
            }
        }
        root.addView(LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(cover, LinearLayout.LayoutParams(DemoUi.dp(ctx, 50), DemoUi.dp(ctx, 50)))
            addView(meta, LinearLayout.LayoutParams(0, -2, 1f))
            addView(button, LinearLayout.LayoutParams(DemoUi.dp(ctx, 30), DemoUi.dp(ctx, 30)))
        })
        if (view.playing) schedule(root, env)
    }

    private fun photoSwap(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card, env: Env) {
        val ctx = root.context
        frame(root, 216, 12, 12, 10, tinted(ctx, 14, tokens().buttonColorPrimaryDefault))
        val now = System.currentTimeMillis()
        val state = DemoCardLocalState.swap(card.instanceId, now)
        val title = when (state) {
            DemoCardLocalState.Swap.INVITED -> if (self) DemoText.get(R.string.demo_you_started_a_photo_swap) else card.payload["text"] ?: DemoText.get(R.string.demo_invited_you_to_swap_photos)
            DemoCardLocalState.Swap.READY -> DemoText.get(R.string.demo_your_demo_photo_is_ready)
            DemoCardLocalState.Swap.REVEALED -> DemoText.get(R.string.demo_demo_photos_swapped)
        }
        root.addView(Host.text(ctx, title, 14f, tokens().textColorPrimary, bold = true))
        val mine = photoName(card.payload["fixtureRef"], "demo_photo_coffee")
        val theirs = photoName("swap_sample_peer", "demo_photo_sea")
        fun slot(label: String, name: String, shown: Boolean) = FrameLayout(ctx).apply {
            background = solid(ctx, 10, tokens().bgColorFunction)
            if (shown && Host.resId(ctx, name) != 0) {
                addView(ImageView(ctx).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    setImageResource(Host.resId(ctx, name))
                }, FrameLayout.LayoutParams(-1, -1))
                Host.roundedClip(this, 10f)
                contentDescription = label
                setOnClickListener { DemoPhotoPreview.show(this, name) }
            } else {
                addView(Host.text(ctx, label, 10f, tokens().textColorSecondary).apply { gravity = Gravity.CENTER },
                    FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
            }
        }
        root.addView(LinearLayout(ctx).apply {
            setPadding(0, DemoUi.dp(ctx, 8), 0, 0)
            addView(slot(DemoText.get(R.string.demo_my_photo), mine, state != DemoCardLocalState.Swap.INVITED),
                LinearLayout.LayoutParams(0, DemoUi.dp(ctx, 76), 1f).apply { marginEnd = DemoUi.dp(ctx, 8) })
            addView(slot(DemoText.get(R.string.demo_their_photo), theirs, state == DemoCardLocalState.Swap.REVEALED),
                LinearLayout.LayoutParams(0, DemoUi.dp(ctx, 76), 1f))
        })
        when (state) {
            DemoCardLocalState.Swap.INVITED -> {
                val label = DemoText.get(R.string.demo_pick_a_demo_photo)
                root.addView(LinearLayout(ctx).apply {
                    setPadding(0, DemoUi.dp(ctx, 8), 0, 0)
                    addView(Host.text(ctx, label, 12f, tokens().textColorButton, bold = true).apply {
                        gravity = Gravity.CENTER
                        background = Host.brandGradient(ctx, 14f)
                        contentDescription = label
                        setOnClickListener {
                            DemoCardLocalState.pickSwap(card.instanceId, System.currentTimeMillis())
                            env.rebind()
                        }
                    }, LinearLayout.LayoutParams(-1, DemoUi.dp(ctx, 28)))
                })
            }
            // The other photo appears half a second after the pick; the re-render is what reveals it.
            DemoCardLocalState.Swap.READY -> schedule(root, env, DemoCardLocalState.swapRevealRemainingMs(card.instanceId, now) + 20)
            DemoCardLocalState.Swap.REVEALED -> Unit
        }
    }

    private fun location(root: LinearLayout, card: DemoCardProtocol.Card) {
        val ctx = root.context
        val t = DemoUi.tokens
        frame(root, 216, 0, 0, 10, solid(ctx, 14, t.bgColorDialog, t.strokeColorPrimary))
        val map = FrameLayout(ctx).apply {
            background = solid(ctx, 0, t.bgColorFunction)
            addView(ImageView(ctx).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                setImageResource(R.drawable.demo_card_map_river)
            }, FrameLayout.LayoutParams(-1, -1))
            addView(centeredGlyph(ctx, R.drawable.demo_ic_map_pin, 32, null).apply { translationY = -DemoUi.dp(ctx, 18).toFloat() })
        }
        root.addView(map, LinearLayout.LayoutParams(-1, DemoUi.dp(ctx, 112)))
        root.addView(LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(DemoUi.dp(ctx, 11), DemoUi.dp(ctx, 9), DemoUi.dp(ctx, 11), 0)
            addView(Host.text(ctx, card.payload["title"] ?: DemoText.get(R.string.demo_demo_place), 12f, t.textColorPrimary, bold = true, single = true))
            addView(Host.text(ctx, card.payload["address"] ?: DemoText.get(R.string.demo_demo_address), 10f, t.textColorTertiary, single = true).apply {
                setPadding(0, DemoUi.dp(ctx, 3), 0, 0)
            })
        })
        roundClip(root, 14)
    }

    private fun roundClip(root: LinearLayout, radiusDp: Int) {
        val radius = DemoUi.dp(root.context, radiusDp).toFloat()
        root.clipToOutline = true
        root.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(v: View, outline: Outline) {
                outline.setRoundRect(0, 0, v.width, v.height, radius)
            }
        }
    }

    /** Burn-after-reading is a square the width of an image bubble; the opened photo fills all of it. */
    private fun burn(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card, env: Env) {
        val ctx = root.context
        val t = tokens()
        val side = 173
        val seconds = DemoCardLocalState.burnSeconds(card.payload["viewSeconds"])
        val view = DemoCardLocalState.burn(card.instanceId, System.currentTimeMillis())
        fun square(background: GradientDrawable, build: FrameLayout.() -> Unit) {
            frame(root, 173, 0, 0, 0, background)
            root.addView(FrameLayout(ctx).apply(build), LinearLayout.LayoutParams(DemoUi.dp(ctx, side), DemoUi.dp(ctx, side)))
            roundClip(root, 14)
        }
        fun centeredColumn(box: FrameLayout, views: List<View>) {
            box.addView(LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(DemoUi.dp(ctx, 14), 0, DemoUi.dp(ctx, 14), 0)
                views.forEach { addView(it) }
            }, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER))
        }
        fun caption(text: String, size: Float, color: Int, bold: Boolean, top: Int) = Host.text(ctx, text, size, color, bold = bold).apply {
            gravity = Gravity.CENTER
            setPadding(0, DemoUi.dp(ctx, top), 0, 0)
        }
        when (view.state) {
            DemoCardLocalState.Burn.SEALED -> {
                square(tinted(ctx, 14, tokens().buttonColorPrimaryDefault, 0.26f, orientation = GradientDrawable.Orientation.TL_BR)) {
                    centeredColumn(this, listOf(
                        glyph(ctx, R.drawable.demo_ic_lock, 30, t.buttonColorPrimaryDefault),
                        caption(if (self) DemoText.get(R.string.demo_private_photo_sent) else DemoText.get(R.string.demo_they_sent_you_a_private_photo), 13f, t.textColorPrimary, true, 8),
                        caption(if (self) DemoText.get(R.string.demo_self_destructs_s_after_they_open_it, seconds) else DemoText.get(R.string.demo_tap_to_view_self_destructs_after_s, seconds), 10f, t.textColorTertiary, false, 8)
                    ))
                }
                if (!self) {
                    root.setOnClickListener {
                        if (DemoCardLocalState.openBurn(card.instanceId, seconds, System.currentTimeMillis())) env.rebind()
                    }
                }
            }
            DemoCardLocalState.Burn.VIEWING -> {
                square(solid(ctx, 14, t.bgColorFunction)) {
                    addView(HostPhoto.tile(ctx, "demo_photo_chengdu"), FrameLayout.LayoutParams(-1, -1))
                    val left = ((view.remainingMs + 999) / 1000).toInt()
                    addView(Host.text(ctx, DemoText.get(R.string.demo_self_destructs_in_s_demo_asset, left), 11f, t.textColorButton, bold = true).apply {
                        gravity = Gravity.CENTER
                        setPadding(DemoUi.dp(ctx, 10), DemoUi.dp(ctx, 4), DemoUi.dp(ctx, 10), DemoUi.dp(ctx, 4))
                        background = solid(ctx, 11, t.bgColorMask)
                    }, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = DemoUi.dp(ctx, 10) })
                }
                schedule(root, env)
            }
            DemoCardLocalState.Burn.EXPIRED -> {
                square(solid(ctx, 14, t.bgColorBubbleReciprocal)) {
                    centeredColumn(this, listOf(
                        glyph(ctx, R.drawable.demo_ic_eye, 26, t.textColorTertiary),
                        caption(DemoText.get(R.string.demo_photo_destroyed), 13f, t.textColorSecondary, true, 8),
                        caption(DemoText.get(R.string.demo_burn_after_reading_viewed), 10f, t.textColorTertiary, false, 8)
                    ))
                }
            }
        }
    }

    /** Demo red packet: no payment, the amount is display-only. The receiver taps once to open; the state is local. */
    private fun redPacket(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card, env: Env): View {
        val ctx = root.context
        val t = tokens()
        val opened = DemoCardLocalState.redPacketOpened(card.instanceId)
        val warm = mix(t.textColorError, t.textColorWarning, 0.4f)
        val start = if (opened) mix(t.textColorError, t.bgColorDialog, 0.45f) else t.textColorError
        val end = if (opened) mix(warm, t.bgColorDialog, 0.45f) else warm
        frame(root, 216, 12, 12, 12, fill(ctx, 14, start, end, orientation = GradientDrawable.Orientation.LEFT_RIGHT))
        val white = t.textColorButton
        val icon = ImageView(ctx).apply {
            setImageResource(R.drawable.demo_card_redpacket)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(DemoUi.dp(ctx, 5), DemoUi.dp(ctx, 5), DemoUi.dp(ctx, 5), DemoUi.dp(ctx, 5))
            background = solid(ctx, 12, Host.alpha(white, 0.92f))
        }
        val value = card.payload["displayValue"] ?: "0"
        val unit = card.payload["displayUnit"] ?: DemoText.get(R.string.demo_fx_diamond_unit)
        val status = when {
            opened -> DemoText.get(R.string.demo_red_packet_opened, value, unit)
            self -> DemoText.get(R.string.demo_red_packet_waiting)
            else -> DemoText.get(R.string.demo_red_packet_tap_to_open)
        }
        root.addView(LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(icon, LinearLayout.LayoutParams(DemoUi.dp(ctx, 44), DemoUi.dp(ctx, 44)))
            addView(LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(DemoUi.dp(ctx, 10), 0, 0, 0)
                addView(Host.text(ctx, card.payload["greeting"] ?: DemoText.get(R.string.demo_red_packet_greeting), 14f, white, bold = true).apply {
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                })
                addView(Host.text(ctx, status, 11f, Host.alpha(white, 0.88f)).apply {
                    maxLines = 1
                    setPadding(0, DemoUi.dp(ctx, 3), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, -2, 1f))
        })
        if (!self && !opened) {
            root.contentDescription = DemoText.get(R.string.demo_red_packet_tap_to_open)
            root.setOnClickListener {
                if (DemoCardLocalState.openRedPacket(card.instanceId)) {
                    env.rebind()
                    root.post {
                        // The rebuilt card has a fresh icon; pulse that one.
                        val fresh = (root.getChildAt(0) as? LinearLayout)?.getChildAt(0)
                        fresh?.let { playEffect("redpacket", it) }
                    }
                }
            }
        }
        return icon
    }

    private fun dice(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card): View {
        val ctx = root.context
        frame(root, 176, 14, 18, 10, brandFill(ctx, 16))
        root.gravity = Gravity.CENTER_HORIZONTAL
        val value = card.payload["value"]?.toIntOrNull()?.coerceIn(1, 6) ?: 1
        val die = DiceFace(ctx, value)
        root.addView(die, LinearLayout.LayoutParams(DemoUi.dp(ctx, 46), DemoUi.dp(ctx, 46)))
        root.addView(Host.text(ctx, DemoText.get(R.string.demo_rolled, if (self) DemoText.get(R.string.demo_you) else DemoText.get(R.string.demo_they), value), 15f, tokens().textColorButton, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(0, DemoUi.dp(ctx, 8), 0, 0)
        })
        root.addView(Host.text(ctx, if (value >= 4) DemoText.get(R.string.demo_the_higher_roll_asks_a_question) else DemoText.get(R.string.demo_the_lower_roll_answers), 10f, Host.alpha(tokens().textColorButton, 0.85f)).apply {
            gravity = Gravity.CENTER
            setPadding(0, DemoUi.dp(ctx, 8), 0, 0)
        })
        return die
    }

    /** Same shell as the dice card; hand and outcome come from the payload, nothing is rolled here. */
    private fun rps(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card): View {
        val ctx = root.context
        frame(root, 112, 10, 12, 8, brandFill(ctx, 16))
        root.gravity = Gravity.CENTER_HORIZONTAL
        val hand = card.payload["hand"]
        val picture = ImageView(ctx).apply {
            setImageResource(DemoRps.handDrawable(hand))
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = DemoRps.handLabel(hand)
        }
        root.addView(picture, LinearLayout.LayoutParams(DemoUi.dp(ctx, 72), DemoUi.dp(ctx, 72)))
        root.addView(Host.text(ctx, DemoRps.handLabel(hand), 13f, tokens().textColorButton, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(0, DemoUi.dp(ctx, 2), 0, 0)
        })
        if (!self) root.setOnClickListener { onReplay(card.kind) }
        return picture
    }

    private fun quiz(root: LinearLayout, card: DemoCardProtocol.Card, env: Env) {
        val ctx = root.context
        frame(root, 218, 13, 14, 10, tinted(ctx, 14, tokens().tagColorLevel4, 0.18f, 0.3f))
        val state = DemoInteractionStore.state(env.conversationId)
        val chosen = state.selection(card.instanceId, DemoInteractionState.LOCAL_ACTOR)
        root.addView(Host.text(ctx, DemoText.get(R.string.demo_crush_quiz_question, card.payload["round"] ?: "1"), 11f, tokens().tagColorLevel4, bold = true))
        root.addView(Host.text(ctx, card.payload["question"] ?: "", 13f, tokens().textColorPrimary).apply {
            setLineSpacing(0f, 1.1f)
            setPadding(0, DemoUi.dp(ctx, 9), 0, DemoUi.dp(ctx, 9))
        })
        val options = LinearLayout(ctx)
        listOf("A" to card.payload["optionA"], "B" to card.payload["optionB"]).filter { it.second != null }
            .forEachIndexed { index, (id, option) ->
                val picked = chosen == id
                options.addView(TextView(ctx).apply {
                    text = if (picked) "✓ $option" else option
                    textSize = 12f
                    gravity = Gravity.CENTER
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(DemoUi.dp(ctx, 6), 0, DemoUi.dp(ctx, 6), 0)
                    setTextColor(if (picked) tokens().tagColorLevel4 else tokens().textColorSecondary)
                    if (picked) setTypeface(typeface, Typeface.BOLD)
                    background = if (picked) solid(ctx, 10, Host.alpha(tokens().tagColorLevel4, 0.16f), Host.alpha(tokens().tagColorLevel4, 0.4f))
                    else solid(ctx, 10, tokens().bgColorFunction, tokens().strokeColorPrimary)
                    contentDescription = if (picked) DemoText.get(R.string.demo_selected, option) else DemoText.get(R.string.demo_select, option)
                    setOnClickListener { selectOption(root, card, env, id) }
                }, LinearLayout.LayoutParams(0, DemoUi.dp(ctx, 32), 1f).apply {
                    if (index == 0) marginEnd = DemoUi.dp(ctx, 8)
                })
            }
        root.addView(options)
        root.addView(Host.text(ctx, if (chosen == null) DemoText.get(R.string.demo_pick_an_answer_local_demo_only_not) else DemoText.get(R.string.demo_your_choice_is_recorded_local_demo_only), 10f, tokens().textColorTertiary).apply {
            setPadding(0, DemoUi.dp(ctx, 8), 0, 0)
        })
    }

    private fun selectOption(root: LinearLayout, card: DemoCardProtocol.Card, env: Env, optionId: String) {
        val state = DemoInteractionStore.state(env.conversationId)
        val outcome = state.apply(
            DemoInteractionState.Event(
                targetInstanceId = card.instanceId,
                eventId = UUID.randomUUID().toString(),
                senderId = DemoInteractionState.LOCAL_ACTOR,
                actorSequence = state.nextSequence(card.instanceId, DemoInteractionState.LOCAL_ACTOR),
                kind = "quiz",
                action = "select",
                params = mapOf("optionId" to optionId)
            )
        )
        if (outcome == DemoInteractionState.Outcome.APPLIED) env.rebind()
    }

    private fun gift(root: LinearLayout, self: Boolean, card: DemoCardProtocol.Card): View {
        val ctx = root.context
        val t = DemoUi.tokens
        frame(root, 196, 12, 12, 10, solid(ctx, 12, t.bgColorDialog, t.strokeColorPrimary))
        val tile = ImageView(ctx).apply {
            setImageResource(DemoGiftIcons.resolve(card.payload["giftRef"]?.toString().orEmpty()))
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        val meta = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(DemoUi.dp(ctx, 10), 0, 0, 0)
            addView(Host.text(ctx, "${card.payload["name"] ?: DemoText.get(R.string.demo_demo_gift)} ×${card.payload["quantity"] ?: "1"}", 14f, t.textColorPrimary, bold = true))
            addView(Host.text(ctx, DemoText.get(R.string.demo_worth, card.payload["displayValue"] ?: "0", card.payload["displayUnit"] ?: ""), 10f, t.textColorSecondary).apply {
                setPadding(0, DemoUi.dp(ctx, 2), 0, 0)
            })
        }
        root.addView(LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(tile, LinearLayout.LayoutParams(DemoUi.dp(ctx, 48), DemoUi.dp(ctx, 48)))
            addView(meta)
        })
        // Only the sender's own card says "已送出"; a received gift no longer invites a gift back.
        if (self) {
            root.addView(View(ctx).apply { setBackgroundColor(t.strokeColorPrimary) },
                LinearLayout.LayoutParams(-1, DemoUi.dp(ctx, 1)).apply {
                    topMargin = DemoUi.dp(ctx, 8)
                    bottomMargin = DemoUi.dp(ctx, 8)
                })
            root.addView(Host.text(ctx, DemoText.get(R.string.demo_sent_demo_gift_no_charge_and_no), 10f, t.textColorSecondary))
        }
        return tile
    }

    private fun schedule(root: LinearLayout, env: Env, delayMs: Long = 500) {
        val tick = Runnable {
            tickers.remove(root)
            if (root.isAttachedToWindow) env.rebind()
        }
        tickers[root] = tick
        root.postDelayed(tick, delayMs)
    }

    private fun playEffect(kind: String, target: View) {
        if (!target.isAttachedToWindow) return
        when (kind) {
            "pat" -> ObjectAnimator.ofFloat(target, View.ROTATION, 0f, -18f, 16f, -12f, 8f, 0f).apply {
                duration = 700
            }.start()
            "dice", "rps" -> ObjectAnimator.ofFloat(target, View.ROTATION, 0f, 720f).apply {
                duration = 650
                interpolator = DecelerateInterpolator()
            }.start()
            "redpacket" -> AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(target, View.SCALE_X, 1f, 1.35f, 0.92f, 1f),
                    ObjectAnimator.ofFloat(target, View.SCALE_Y, 1f, 1.35f, 0.92f, 1f)
                )
                duration = 500
            }.start()
            "gift" -> {
                AnimatorSet().apply {
                    playTogether(
                        ObjectAnimator.ofFloat(target, View.SCALE_X, 1f, 1.3f, 1f),
                        ObjectAnimator.ofFloat(target, View.SCALE_Y, 1f, 1.3f, 1f)
                    )
                    duration = 600
                    interpolator = OvershootInterpolator()
                }.start()
                DemoHeartBurst.play(target)
            }
        }
    }

    private fun unsupported(root: LinearLayout) {
        val ctx = root.context
        frame(root, 232, 12, 14, 10, solid(ctx, 14, DemoUi.tokens.bgColorBubbleReciprocal))
        root.addView(Host.text(ctx, DemoText.get(R.string.demo_unsupported_demo_card_update_the_demo_to), 12f, DemoUi.tokens.textColorSecondary))
    }

    private fun clock(ms: Long): String {
        val total = ms / 1000
        return "${total / 60}:${(total % 60).toString().padStart(2, '0')}"
    }

    private class DiceFace(context: Context, private val value: Int) : View(context) {
        private val ends = DemoUi.tokens.let { t ->
            listOf(t.textColorButton, t.textColorPrimary, t.bgColorDialog)
                .sortedBy { androidx.core.graphics.ColorUtils.calculateLuminance(it) }
        }
        private val face = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ends.last() }
        private val dot = Paint(Paint.ANTI_ALIAS_FLAG)

        override fun onDraw(canvas: Canvas) {
            val d = resources.displayMetrics.density
            val size = 40 * d
            val left = (width - size) / 2
            val top = (height - size) / 2
            canvas.drawRoundRect(RectF(left, top, left + size, top + size), 9 * d, 9 * d, face)
            val cells = when (value) {
                1 -> listOf(5)
                2 -> listOf(1, 9)
                3 -> listOf(1, 5, 9)
                4 -> listOf(1, 3, 7, 9)
                5 -> listOf(1, 3, 5, 7, 9)
                else -> listOf(1, 3, 4, 6, 7, 9)
            }
            val innerW = size - 13 * d
            val innerH = size - 11 * d
            cells.forEach { cell ->
                val col = (cell - 1) % 3
                val row = (cell - 1) / 3
                val cx = left + 6.5f * d + innerW / 3 * (col + 0.5f)
                val cy = top + 5.5f * d + innerH / 3 * (row + 0.5f)
                dot.color = if (cell == 1 || cell == 9 || value == 1) DemoUi.tokens.tagColorLevel4
                else ends.first()
                canvas.drawCircle(cx, cy, 3.25f * d, dot)
            }
        }
    }

    companion object {

        val summaryProvider = MessageSummaryProvider { summaryContext ->
            val data = (summaryContext.message.messagePayload as? CustomMessagePayload)?.customData
            DemoCardProtocol.summary(DemoCardProtocol.parse(data))
        }
    }
}
