package io.trtc.tuikit.chat.demo.chat

import android.animation.ValueAnimator
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.mock.DemoGift
import io.trtc.tuikit.chat.demo.mock.DemoGiftPanel
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import kotlin.math.abs
import kotlin.math.max
import kotlin.random.Random

/**
 * Gift chooser. There is no design export for this sheet (the prototype's chat gift button
 * sends one fixed gift), so it is composed from the existing tokens: `.sheet` surface r16, gift-card
 * gold tile 12, brand-gradient send pill. Each tap sends one real `chat.card` gift message; the
 * combo only decorates this panel and never touches a wallet (spec 03 §5).
 */
class GiftPanelDialog(
    context: Context,
    private val panel: DemoGiftPanel,
    private val onSend: (gift: DemoGift, done: (combo: Int?) -> Unit) -> Unit
) : Dialog(context) {

    private val tiles = mutableListOf<Pair<DemoGift, LinearLayout>>()
    private var selected = panel.gifts.firstOrNull()
    private var busy = false
    private lateinit var sendLabel: TextView
    private lateinit var comboLabel: TextView
    private lateinit var sendButton: FrameLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window?.apply {
            // The default dialog window keeps a decor inset on both sides; clear it so the sheet is edge to edge (like iOS).
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
            decorView.setPadding(0, 0, 0, 0)
            setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
            setGravity(Gravity.BOTTOM)
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(0.45f)
        }
        setContentView(build())
        select(selected ?: panel.gifts.firstOrNull())
    }

    private fun build(): View {
        val t = DemoUi.tokens
        val context = context
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                setColor(t.bgColorDialog)
                cornerRadii = floatArrayOf(16f, 16f, 16f, 16f, 0f, 0f, 0f, 0f)
                    .map { it * resources.displayMetrics.density }.toFloatArray()
            }
            setPadding(dp(16), dp(16), dp(16), dp(16) + navigationBarHeight())
        }
        column.addView(LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(Host.text(context, panel.title, 16f, t.textColorPrimary, bold = true))
        })

        val grid = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            weightSum = 4f
        }
        panel.gifts.take(4).forEach { gift ->
            val tile = tile(gift)
            tiles += gift to tile
            grid.addView(tile, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
        column.addView(grid, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })

        sendButton = FrameLayout(context).apply {
            background = Host.brandGradient(context, 22f)
            addView(Host.text(context, "", 15f, t.textColorButton, bold = true), FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
            isClickable = true
            setOnClickListener { send() }
        }
        sendLabel = sendButton.getChildAt(0) as TextView
        val buttonWrap = FrameLayout(context).apply {
            clipChildren = false
            clipToPadding = false
        }
        comboLabel = Host.text(context, "", 22f, t.textColorWarning, bold = true).apply {
            visibility = View.INVISIBLE
            gravity = Gravity.CENTER
        }
        buttonWrap.addView(sendButton, FrameLayout.LayoutParams(-1, dp(44), Gravity.BOTTOM))
        buttonWrap.addView(comboLabel, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        column.addView(buttonWrap, LinearLayout.LayoutParams(-1, dp(68)).apply { topMargin = dp(10) })
        return column
    }

    private fun tile(gift: DemoGift): LinearLayout {
        val t = DemoUi.tokens
        val context = context
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            isClickable = true
            setOnClickListener { select(gift) }
        }
        val base = FrameLayout(context).apply {
            background = tileBackground(false)
            addView(ImageView(context).apply {
                setImageResource(DemoGiftIcons.resolve(gift.ref))
                scaleType = ImageView.ScaleType.FIT_CENTER
            }, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER))
        }
        column.addView(base, LinearLayout.LayoutParams(dp(64), dp(64)))
        column.addView(Host.text(context, gift.name, 11f, t.textColorSecondary, single = true),
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(6) })
        column.addView(Host.text(context, "${gift.value} ${gift.unit}", 10f, t.textColorTertiary, single = true),
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(1) })
        return column
    }

    private fun select(gift: DemoGift?) {
        selected = gift ?: return
        tiles.forEach { (item, column) ->
            val on = item.ref == gift.ref
            column.getChildAt(0).background = tileBackground(on)
            column.alpha = if (on) 1f else 0.86f
        }
        sendLabel.text = "${panel.sendText}「${gift.name}」"
    }

    private fun tileBackground(selected: Boolean) = GradientDrawable().apply {
        setColor(androidx.core.graphics.ColorUtils.setAlphaComponent(DemoUi.tokens.textColorPrimary, if (selected) 28 else 14))
        cornerRadius = dp(16).toFloat()
        if (selected) setStroke(dp(2), DemoUi.tokens.buttonColorPrimaryDefault)
    }

    private fun send() {
        val gift = selected ?: return
        if (busy) return
        busy = true
        sendButton.alpha = 0.7f
        onSend(gift) { combo ->
            busy = false
            sendButton.alpha = 1f
            if (combo != null) showCombo(combo)
        }
    }

    private fun showCombo(combo: Int) {
        comboLabel.text = "×$combo"
        comboLabel.visibility = View.VISIBLE
        comboLabel.animate().cancel()
        comboLabel.alpha = 0f
        comboLabel.translationY = Host.dpf(context, 18f)
        comboLabel.scaleX = 0.7f
        comboLabel.scaleY = 0.7f
        comboLabel.animate()
            .alpha(1f).translationY(0f).scaleX(1.1f).scaleY(1.1f)
            .setDuration(160)
            .withEndAction {
                comboLabel.animate().alpha(0f).translationY(-Host.dpf(context, 12f))
                    .setDuration(420).setStartDelay(600)
                    .withEndAction { comboLabel.visibility = View.INVISIBLE }.start()
            }
            .start()
    }

    private fun dp(value: Int) = DemoUi.dp(context, value)

    private fun navigationBarHeight(): Int {
        val id = context.resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (id > 0) context.resources.getDimensionPixelSize(id) else 0
    }
}

/** giftRef -> bundled glyph (explicit: R8 keeps only referenced drawables). */
object DemoGiftIcons {
    private val MAP = mapOf(
        "star_candy" to R.drawable.demo_gift_star_candy,
        "autumn_tea" to R.drawable.demo_gift_autumn_tea,
        "little_heart" to R.drawable.demo_gift_little_heart,
        "mystery_box" to R.drawable.demo_gift_mystery_box
    )

    fun resolve(giftRef: String): Int = MAP[giftRef] ?: R.drawable.demo_gift_mystery_box
}

/** Shared payload/summary builder so the panel and the quick row send identical cards. */
object DemoGiftCard {
    val SUMMARY: String get() = DemoText.get(R.string.demo_gift)

    fun payload(gift: DemoGift): Map<String, Any> = mapOf(
        "giftRef" to gift.ref,
        "name" to gift.name,
        "quantity" to 1,
        "displayValue" to gift.value,
        "displayUnit" to gift.unit
    )

    /** Retry key: a failed send is retried as the same interaction, a successful one starts a new card. */
    fun key(gift: DemoGift): String = "gift:${gift.ref}"
}

/**
 * One-shot gift hearts (prototype `.flyheart`, design S10): 6-8 small hearts rise from the
 * gift card and fade out over ~2s. Decorative only, skipped when the system has animations off.
 */
object DemoHeartBurst {
    private const val DURATION_MS = 2000L
    private const val STAGGER_MS = 90L
    private const val HEART_COUNT = 7

    fun play(anchor: View, count: Int = HEART_COUNT) {
        val root = anchor.rootView as? ViewGroup ?: return
        if (!anchor.isAttachedToWindow || animationsDisabled(anchor.context)) return
        val location = IntArray(2).also { anchor.getLocationInWindow(it) }
        val rootLocation = IntArray(2).also { root.getLocationInWindow(it) }
        val originX = (location[0] - rootLocation[0] + anchor.width / 2).toFloat()
        val originY = (location[1] - rootLocation[1]).toFloat()

        repeat(count) { index ->
            val context = anchor.context
            val sizeDp = 14 + Random.nextInt(0, 12)
            val heart = ImageView(context).apply {
                setImageResource(resolveHeart(context))
                setColorFilter(DemoUi.tokens.tagColorLevel4)
                alpha = 0f
                scaleX = 0.4f
                scaleY = 0.4f
            }
            val startX = originX + Random.nextInt(-24, 24)
            root.addView(heart, ViewGroup.LayoutParams(Host.dp(context, sizeDp), Host.dp(context, sizeDp)))
            val drift = Random.nextInt(-52, 52).toFloat()
            val rise = Host.dpf(context, 200f) + Random.nextInt(0, 60)
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = DURATION_MS
                startDelay = index * STAGGER_MS
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    val t = animator.animatedValue as Float
                    heart.translationX = startX + drift * t
                    heart.translationY = originY - rise * t
                    heart.scaleX = 0.4f + 0.6f * minOf(t / 0.15f, 1f)
                    heart.scaleY = heart.scaleX
                    heart.alpha = when {
                        t < 0.15f -> t / 0.15f
                        else -> max(0f, 1f - (t - 0.15f) / 0.85f)
                    }
                }
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        (heart.parent as? ViewGroup)?.removeView(heart)
                    }
                })
                start()
            }
        }
    }

    private fun resolveHeart(context: Context): Int =
        io.trtc.tuikit.chat.demo.R.drawable.demo_ic_heart_big

    private fun animationsDisabled(context: Context): Boolean = try {
        abs(Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)) == 0f
    } catch (_: Exception) {
        false
    }
}

/**
 * Local gift combo counter (spec 03 §5). It only drives the "x N" pop in the gift panel;
 * it is not a ledger, never touches a wallet and is never sent. Counting happens on a successful send,
 * keyed by the card's instanceId, so a retried send of the same card cannot bump the combo twice.
 */
object DemoGiftCombo {
    const val DEFAULT_WINDOW_MS = 2600L
    private const val MAX_REMEMBERED = 64

    private var lastRef: String? = null
    private var lastAtMs = 0L
    private var count = 0
    private val counted = LinkedHashMap<String, Int>()

    /** Registers one successfully sent gift; the same [instanceId] always returns the combo it first produced. */
    @Synchronized
    fun register(instanceId: String, giftRef: String, nowMs: Long, windowMs: Long = DEFAULT_WINDOW_MS): Int {
        if (instanceId.isNotBlank()) counted[instanceId]?.let { return it }
        count = if (giftRef == lastRef && nowMs - lastAtMs in 0 until windowMs) count + 1 else 1
        lastRef = giftRef
        lastAtMs = nowMs
        if (instanceId.isNotBlank()) {
            counted[instanceId] = count
            if (counted.size > MAX_REMEMBERED) counted.remove(counted.keys.first())
        }
        return count
    }

    @Synchronized
    fun reset() {
        lastRef = null
        lastAtMs = 0L
        count = 0
        counted.clear()
    }
}
