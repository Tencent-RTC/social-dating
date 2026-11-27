package io.trtc.tuikit.chat.hostbase

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.res.ResourcesCompat
import androidx.core.graphics.ColorUtils

/**
 * Hard metrics of the V2 host shell, taken from the prototype tokens (`tokens.css :root`) and
 * `uikit.css`. 1dp = 1px of the 360 x 800 design frame. The iOS host uses the same numbers in
 * `HostMetrics` (TUIHostBase/Sources/HostWidgets.swift); `tools/tests/test_host_shell.py` keeps the two in sync.
 */
object HostMetrics {
    const val PAGE_HEADER_H = 48
    const val PAGE_TITLE_SP = 19f
    const val SEG_BAR_H = 44
    const val SEARCH_BAR_H = 36
    const val SEARCH_BAR_RADIUS = 10
    const val CONV_ITEM_H = 72

    /** Home card nickname / intro: same sizes as the conversation row title (18) and subtitle (14). */
    const val USER_CARD_NAME_SP = 18f
    const val USER_CARD_META_SP = 14f
    const val CONV_AVATAR = 48
    const val SCREEN_PADDING_H = 16

    /**
     * Back arrow margin. The arrow view is a 40dp touch target whose glyph is inset 10dp, so 4dp puts the visible
     * chevron at 20dp from the edge — the same place on the chat page, the settings page and every header page.
     */
    const val BACK_BUTTON_MARGIN = 4
    const val CARD_RADIUS = 14

    // Bottom tab bar
    const val TAB_BAR_H = 64
    const val TAB_ITEM_H = 54
    const val TAB_ICON = 28
    const val TAB_LABEL_SP = 12
    const val TAB_BADGE = 18
    const val TAB_BADGE_RING = 2
    const val TAB_BADGE_OFFSET_TOP = -3
    const val TAB_BADGE_OFFSET_LEFT = 16
    const val TAB_BADGE_ROOM = 16

    // Segment tabs
    const val SEG_GAP = 20
    const val SEG_GAP_TIGHT = 18
    const val SEG_TEXT_SP = 18
    const val SEG_TEXT_ON_SP = 20
    const val SEG_UNDERLINE_W = 16
    const val SEG_UNDERLINE_H = 3

    // Home user card
    const val USER_CARD_GAP = 12
    const val USER_CARD_MASK_H = 64
    const val DIST_TAG_H = 18
    const val SEX_TAG_H = 16

    // Mine
    const val ME_AVATAR = 72
    const val ME_BLOCK_GAP = 8
    const val WALLET_H = 80
    const val WALLET_RADIUS = 14
    const val MENU_ROW_H = 56

    /** Home cards are two per row; the width follows the screen, 158dp on the 360dp frame. */
    fun userCardWidth(screenWidthDp: Float): Float =
        (screenWidthDp - 2 * SCREEN_PADDING_H - USER_CARD_GAP) / 2f
}

enum class TagKind { AGE_MALE, AGE_FEMALE, CITY, HEIGHT, VERIFIED }

/**
 * Shared builders for the V2 host shell (tab bar, page header, segment tabs, tags). Every
 * colour is read from the current social palette on each build; a palette or light/dark change
 * rebuilds the activity (see DemoActivity.onResume), so nothing is cached here.
 */
object Host {
    private val tokens get() = DemoUi.tokens

    /** The one colour token of a tag class; every page (profile, chat title, lists, home card) reads it from here. */
    fun tagAccent(kind: TagKind): Int = when (kind) {
        TagKind.AGE_MALE -> tokens.tagColorLevel1
        TagKind.AGE_FEMALE -> tokens.tagColorLevel4
        TagKind.CITY -> tokens.tagColorLevel2
        TagKind.HEIGHT -> tokens.textColorWarning
        TagKind.VERIFIED -> tokens.tagColorLevel1
    }

    /** Age / gender tag class of a peer: male = blue-ish token, female = pink token. */
    fun ageKind(sex: String): TagKind = if (sex == "m") TagKind.AGE_MALE else TagKind.AGE_FEMALE

    fun dp(context: Context, value: Int): Int = DemoUi.dp(context, value)
    fun dpf(context: Context, value: Float): Float = value * context.resources.displayMetrics.density

    fun alpha(color: Int, fraction: Float): Int = ColorUtils.setAlphaComponent(color, (fraction * 255).toInt())

    fun hapticConfirm(view: View) {
        val constant = if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        view.performHapticFeedback(constant)
    }

    /** Brand gradient (`--brandGradient`): buttonColorPrimaryDefault to tagColorLevel4, left to right. */
    fun brandGradient(context: Context, radiusDp: Float, oval: Boolean = false) =
        GradientDrawable(
            GradientDrawable.Orientation.LEFT_RIGHT,
            intArrayOf(tokens.buttonColorPrimaryDefault, tokens.tagColorLevel4)
        ).apply {
            if (oval) shape = GradientDrawable.OVAL else cornerRadius = dpf(context, radiusDp)
        }

    fun showThemed(
        context: Context,
        builder: android.app.AlertDialog.Builder,
        positiveColor: Int? = null
    ): android.app.AlertDialog {
        val dialog = builder.create()
        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawable(rounded(context, tokens.bgColorDialog, 16f, tokens.strokeColorPrimary))
            dialog.findViewById<TextView>(android.R.id.message)?.setTextColor(tokens.textColorSecondary)
            dialog.findViewById<TextView>(context.resources.getIdentifier("alertTitle", "id", "android"))
                ?.setTextColor(tokens.textColorPrimary)
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE)?.setTextColor(positiveColor ?: tokens.textColorLink)
            dialog.getButton(android.app.AlertDialog.BUTTON_NEGATIVE)?.setTextColor(tokens.textColorLink)
        }
        dialog.show()
        return dialog
    }

    fun rounded(context: Context, color: Int, radiusDp: Float, strokeColor: Int? = null) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dpf(context, radiusDp)
            if (strokeColor != null) setStroke(dp(context, 1).coerceAtLeast(1), strokeColor)
        }

    fun text(
        context: Context, value: CharSequence, sizeSp: Float, color: Int,
        bold: Boolean = false, single: Boolean = false
    ) = TextView(context).apply {
        text = value
        textSize = sizeSp
        setTextColor(color)
        includeFontPadding = false
        if (bold) setTypeface(typeface, Typeface.BOLD)
        if (single) {
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
    }

    /** Template glyph (white PNG) tinted with [tint]; [sizeDp] is the design size. */
    fun icon(context: Context, drawableRes: Int, sizeDp: Int, tint: Int? = null) =
        ImageView(context).apply {
            setImageResource(drawableRes)
            scaleType = ImageView.ScaleType.FIT_CENTER
            if (tint != null) setColorFilter(tint, PorterDuff.Mode.SRC_IN)
            layoutParams = LinearLayout.LayoutParams(dp(context, sizeDp), dp(context, sizeDp))
        }

    fun resId(context: Context, name: String): Int =
        context.resources.getIdentifier(name, "drawable", context.packageName)

    fun roundedClip(view: View, radiusDp: Float) {
        val radius = dpf(view.context, radiusDp)
        view.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(v: View, outline: Outline) =
                outline.setRoundRect(0, 0, v.width, v.height, radius)
        }
        view.clipToOutline = true
    }

    fun circleClip(view: View) {
        view.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(v: View, outline: Outline) =
                outline.setOval(0, 0, v.width, v.height)
        }
        view.clipToOutline = true
    }

    // ------------------------------------------------------------------ tags

    private fun tagBase(context: Context, background: Int) = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        this.background = rounded(context, background, 5f)
    }

    /** `.tag--verified`: shield 10 + text; dark palettes lift the text one step towards white. */
    fun verifiedTag(context: Context, label: String): View {
        val base = tagAccent(TagKind.VERIFIED)
        val ink = if (DemoUi.isDark) ColorUtils.blendARGB(base, Color.WHITE, 0.22f) else base
        return tagBase(context, alpha(base, 0.18f)).apply {
            setPadding(dp(context, 5), 0, dp(context, 6), 0)
            addView(icon(context, R.drawable.demo_ic_shield, 10, ink),
                LinearLayout.LayoutParams(dp(context, 10), dp(context, 10)).apply { marginEnd = dp(context, 3) })
            addView(text(context, label, 10f, ink))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(context, 18))
        }
    }

    /** `.sextag`: gender glyph 10 + age, h16 r8; male = tagColorLevel1 (blue), female = tagColorLevel4 (pink); the glyph repeats the gender. */
    fun sexTag(context: Context, sex: String, age: Int): View {
        val male = sex == "m"
        val accent = tagAccent(ageKind(sex))
        val ink = if (DemoUi.isDark) ColorUtils.blendARGB(accent, Color.WHITE, 0.30f) else accent
        val fill = alpha(accent, 0.18f)
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = rounded(context, fill, 8f)
            setPadding(dp(context, 5), 0, dp(context, 6), 0)
            addView(icon(context, if (male) R.drawable.demo_ic_male else R.drawable.demo_ic_female, 10, ink),
                LinearLayout.LayoutParams(dp(context, 10), dp(context, 10)).apply { marginEnd = dp(context, 2) })
            addView(text(context, age.toString(), 10f, ink))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(context, HostMetrics.SEX_TAG_H))
        }
    }

    /** Back arrow shared by every host page: 20dp glyph in a 40dp tap target, textColorPrimary. */
    fun backButton(context: Context, onClick: () -> Unit): ImageView =
        icon(context, R.drawable.demo_hd_back, 20, tokens.textColorPrimary).apply {
            contentDescription = DemoText.get(R.string.demo_back)
            setPadding(dp(context, 10), dp(context, 10), dp(context, 10), dp(context, 10))
            layoutParams = LinearLayout.LayoutParams(dp(context, 40), dp(context, 40))
            setOnClickListener { onClick() }
        }

    /** `.metatag`: solid tagColorLevelN pill with `textColorButton` 10 text, used for city / age / height. */
    fun metaTag(context: Context, label: String, accent: Int, heightDp: Int = HostMetrics.DIST_TAG_H,
                radiusDp: Float = 9f, textColor: Int = tokens.textColorButton, textSp: Float = 10f): TextView =
        text(context, label, textSp, textColor).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            maxLines = 1
            setPadding(dp(context, 6), 0, dp(context, 7), 0)
            background = rounded(context, alpha(accent, 0.92f), radiusDp)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(context, heightDp))
        }

    /** Solid chip of a tag class: always [metaTag] filled with that class's [tagAccent]. */
    fun kindTag(context: Context, kind: TagKind, label: String, heightDp: Int = HostMetrics.DIST_TAG_H,
                radiusDp: Float = 9f, textSp: Float = 10f): TextView =
        metaTag(context, label, tagAccent(kind), heightDp, radiusDp, tokens.textColorButton, textSp)

    /** The one colour of every unread indicator (count badge, red dot) on every page: the error token. */
    val unreadAccent: Int get() = tokens.textColorError

    /** Count badge (`.badge`): h18 min-w17 pill, [unreadAccent] with textColorButton bold 11. */
    fun badge(context: Context, count: Int, ringColor: Int? = null, sizeDp: Int = 18, textSp: Float = 11f): TextView =
        TextView(context).apply {
            text = if (count > 99) "99+" else count.toString()
            textSize = textSp
            setTextColor(tokens.textColorButton)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            includeFontPadding = false
            minWidth = dp(context, sizeDp - 1)
            minHeight = dp(context, sizeDp)
            setPadding(dp(context, 5), 0, dp(context, 5), 0)
            background = GradientDrawable().apply {
                cornerRadius = dpf(context, sizeDp / 2f)
                setColor(unreadAccent)
                if (ringColor != null) setStroke(dp(context, HostMetrics.TAB_BADGE_RING), ringColor)
            }
        }
}

/**
 * Selected tab glyph: the white alpha mask is filled with the palette gradient
 * (buttonColorPrimaryDefault to tagColorLevel4, top-left to bottom-right) and the white
 * details are drawn on top, exactly like the design's "图标/Tab" selected state.
 */
class GradientGlyphView(context: Context, shapeRes: Int, detailRes: Int) : View(context) {
    private val shape = ResourcesCompat.getDrawable(resources, shapeRes, null)
    private val detail = ResourcesCompat.getDrawable(resources, detailRes, null)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN) }

    override fun onDraw(canvas: Canvas) {
        val w = width
        val h = height
        if (w == 0 || h == 0) return
        val layer = canvas.saveLayer(0f, 0f, w.toFloat(), h.toFloat(), null)
        shape?.setBounds(0, 0, w, h)
        shape?.draw(canvas)
        paint.shader = LinearGradient(0f, 0f, w.toFloat(), h.toFloat(),
            DemoUi.tokens.buttonColorPrimaryDefault, DemoUi.tokens.tagColorLevel4, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        canvas.restoreToCount(layer)
        detail?.setBounds(0, 0, w, h)
        detail?.draw(canvas)
    }
}

/** Page header: 48dp, centred 17sp bold title, optional left slot and right action icons. */
class HostHeader(
    context: Context,
    title: String,
    left: View? = null,
    ops: List<View> = emptyList(),
    opsGapDp: Int = 14
) : FrameLayout(context) {
    init {
        val colors = DemoUi.tokens
        setBackgroundColor(colors.bgColorTopBar)
        layoutParams = LinearLayout.LayoutParams(-1, Host.dp(context, HostMetrics.PAGE_HEADER_H))
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        addView(Host.text(context, title, HostMetrics.PAGE_TITLE_SP, colors.textColorPrimary, bold = true, single = true).apply {
            gravity = Gravity.CENTER
        }, LayoutParams(-2, -2, Gravity.CENTER))
        if (left != null) {
            // The back button carries its own 10dp glyph inset inside a 40dp touch target, so the header only adds
            // BACK_BUTTON_MARGIN — matching the chat page instead of indenting the arrow by the content padding.
            addView(left, LayoutParams(-2, -2, Gravity.START or Gravity.CENTER_VERTICAL).apply {
                marginStart = Host.dp(context, HostMetrics.BACK_BUTTON_MARGIN)
            })
        }
        if (ops.isNotEmpty()) {
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                ops.forEachIndexed { index, op ->
                    addView(op, LinearLayout.LayoutParams(op.layoutParams?.width ?: -2, op.layoutParams?.height ?: -2).apply {
                        if (index > 0) marginStart = Host.dp(context, opsGapDp)
                    })
                }
            }, LayoutParams(-2, -2, Gravity.END or Gravity.CENTER_VERTICAL).apply { marginEnd = pad })
        }
    }
}

/**
 * Segment tabs (`.segbar`): 44dp, text 18 secondary / 20 bold primary + 16x3 underline, optional right control.
 *
 * The bar is driven by a continuous position ([setPosition], `0..n-1`): a pager reports where it is every frame (tap
 * slide, finger drag and the settle after release alike), so labels and underline travel with the pages instead of
 * switching when they land. Each label's weight is `1 - |position - index|`: size 18 -> 20, colour secondary -> primary and a
 * bold copy fading in over the regular one. The single underline stretches between two tabs (leading edge runs ahead of
 * the trailing one) and settles back to 16dp.
 */
class HostSegBar(
    context: Context,
    titles: List<String>,
    selected: Int,
    tight: Boolean = false,
    right: View? = null,
    private val onSelect: (Int) -> Unit
) : FrameLayout(context) {
    private val labels = mutableListOf<TextView>()
    private val boldLabels = mutableListOf<TextView>()
    private val spacers = mutableListOf<View>()
    private val badgeHolders = mutableListOf<FrameLayout>()
    private val badgeCounts = mutableMapOf<Int, Int>()
    private val indicator = Indicator(context)
    private val rect = android.graphics.Rect()
    private var position = -1f
    private val sizes = FloatArray(titles.size) { HostMetrics.SEG_TEXT_SP.toFloat() }

    private class Indicator(context: Context) : View(context) {
        var left = 0f
        var right = 0f
        var top = 0f
        var bottom = 0f
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = DemoUi.tokens.buttonColorPrimaryDefault }
        private val radius = Host.dpf(context, 2f)

        override fun onDraw(canvas: Canvas) {
            if (right > left) canvas.drawRoundRect(left, top, right, bottom, radius, radius, paint)
        }
    }

    init {
        val colors = DemoUi.tokens
        clipChildren = false
        setBackgroundColor(colors.bgColorTopBar)
        layoutParams = LinearLayout.LayoutParams(-1, Host.dp(context, HostMetrics.SEG_BAR_H))
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            clipChildren = false
            titles.forEachIndexed { index, title ->
                val label = Host.text(context, title, HostMetrics.SEG_TEXT_SP.toFloat(), colors.textColorSecondary)
                val bold = Host.text(context, title, HostMetrics.SEG_TEXT_SP.toFloat(), colors.textColorSecondary, bold = true)
                val badgeHolder = FrameLayout(context).apply { clipChildren = false }
                badgeHolders += badgeHolder
                // Keeps the room (and the position) of the underline; the visible one is the shared [indicator].
                val spacer = View(context).apply { visibility = INVISIBLE }
                labels += label
                boldLabels += bold
                spacers += spacer
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    clipChildren = false
                    addView(FrameLayout(context).apply {
                        clipChildren = false
                        addView(label, FrameLayout.LayoutParams(-2, -2))
                        addView(bold, FrameLayout.LayoutParams(-2, -2))
                        addView(badgeHolder, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.END).apply {
                            marginEnd = -Host.dp(context, 10)
                            topMargin = -Host.dp(context, 7)
                        })
                    }, LinearLayout.LayoutParams(-2, -2))
                    addView(spacer, LinearLayout.LayoutParams(Host.dp(context, HostMetrics.SEG_UNDERLINE_W),
                        Host.dp(context, HostMetrics.SEG_UNDERLINE_H)).apply { topMargin = Host.dp(context, 4) })
                    // The pager answers with the position; nothing is switched here, so a tap and a swipe look the same.
                    setOnClickListener { onSelect(index) }
                    contentDescription = title
                }, LinearLayout.LayoutParams(-2, -2).apply {
                    if (index > 0) marginStart = Host.dp(context, if (tight) HostMetrics.SEG_GAP_TIGHT else HostMetrics.SEG_GAP)
                })
            }
        }, LayoutParams(-2, -2, Gravity.START or Gravity.CENTER_VERTICAL).apply { marginStart = pad })
        if (right != null) {
            addView(right, LayoutParams(-2, -2, Gravity.END or Gravity.CENTER_VERTICAL).apply { marginEnd = pad })
        }
        addView(indicator, LayoutParams(-1, -1))
        select(selected, notify = false)
    }

    fun setBadge(index: Int, count: Int) {
        val holder = badgeHolders.getOrNull(index) ?: return
        val previous = badgeCounts[index] ?: 0
        badgeCounts[index] = count
        holder.removeAllViews()
        if (count <= 0) return
        val badge = Host.badge(context, count, ringColor = DemoUi.tokens.bgColorTopBar, sizeDp = 16, textSp = 10f)
        holder.addView(badge)
        if (count > previous && previous >= 0 && isAttachedToWindow) Motion.bump(badge)
    }

    /** Jumps to [index] with no transition; [notify] reports it to the select callback. */
    fun select(index: Int, notify: Boolean) {
        setPosition(index.toFloat())
        if (notify) onSelect(index)
    }

    /** Continuous position between tabs: `1.5` is half way from the second tab to the third. */
    fun setPosition(value: Float) {
        val p = value.coerceIn(0f, (labels.size - 1).coerceAtLeast(0).toFloat())
        if (p == position) return
        position = p
        val colors = DemoUi.tokens
        labels.forEachIndexed { i, label ->
            val w = (1f - kotlin.math.abs(p - i)).coerceIn(0f, 1f)
            val size = HostMetrics.SEG_TEXT_SP + (HostMetrics.SEG_TEXT_ON_SP - HostMetrics.SEG_TEXT_SP) * w
            val color = ColorUtils.blendARGB(colors.textColorSecondary, colors.textColorPrimary, w)
            val bold = boldLabels[i]
            if (kotlin.math.abs(sizes[i] - size) > 0.02f) {
                sizes[i] = size
                label.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, size)
                bold.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, size)
            }
            label.setTextColor(color)
            bold.setTextColor(color)
            // Bold fades in over the regular copy (never both below full opacity), so the weight changes without a pop.
            bold.alpha = (w * 2f).coerceAtMost(1f)
            label.alpha = ((1f - w) * 2f).coerceAtMost(1f)
        }
        placeIndicator()
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        placeIndicator()
    }

    private fun placeIndicator() {
        if (spacers.isEmpty() || position < 0f || width == 0) return
        val first = kotlin.math.floor(position).toInt().coerceIn(0, spacers.size - 1)
        val second = (first + 1).coerceAtMost(spacers.size - 1)
        val t = (position - first).coerceIn(0f, 1f)
        fun edges(index: Int): Pair<Float, Float> {
            val spacer = spacers[index]
            rect.set(0, 0, spacer.width, spacer.height)
            offsetDescendantRectToMyCoords(spacer, rect)
            indicator.top = rect.top.toFloat()
            indicator.bottom = rect.bottom.toFloat()
            return rect.left.toFloat() to rect.right.toFloat()
        }
        val (l0, r0) = edges(first)
        val (l1, r1) = edges(second)
        // The edge in front runs ahead of the one behind, so the line stretches while it travels and relaxes on arrival.
        val ahead = 1f - Math.pow((1f - t).toDouble(), STRETCH).toFloat()
        val behind = Math.pow(t.toDouble(), STRETCH).toFloat()
        indicator.left = l0 + (l1 - l0) * behind
        indicator.right = r0 + (r1 - r0) * ahead
        indicator.invalidate()
    }

    private companion object {
        const val STRETCH = 1.7
    }
}

/**
 * Bottom tab bar (`.tabbar`): 56dp, bgColorBottomBar with a 1px top stroke. Selected glyphs use the
 * palette gradient, labels 10sp (selected = textColorLink bold), message badge 18dp with a 2dp ring.
 */
class HostTabBar(
    context: Context,
    private val labels: List<String>,
    private val onSelect: (Int) -> Unit
) : LinearLayout(context) {
    private class Item(val off: ImageView, val on: GradientGlyphView, val label: TextView, val column: LinearLayout)

    private val items = mutableListOf<Item>()
    private var badge: TextView? = null
    private val offIcons = listOf(R.drawable.demo_tab_home, R.drawable.demo_tab_chat, R.drawable.demo_tab_mine)
    private val onShapes = listOf(R.drawable.demo_tab_home_on_shape, R.drawable.demo_tab_chat_on_shape, R.drawable.demo_tab_mine_on_shape)
    private val onDetails = listOf(R.drawable.demo_tab_home_on_detail, R.drawable.demo_tab_chat_on_detail, R.drawable.demo_tab_mine_on_detail)

    init {
        val colors = DemoUi.tokens
        orientation = VERTICAL
        setBackgroundColor(colors.bgColorBottomBar)
        addView(View(context).apply { setBackgroundColor(colors.strokeColorPrimary) }, LayoutParams(-1, Host.dp(context, 1).coerceAtLeast(1)))
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        addView(row, LayoutParams(-1, Host.dp(context, HostMetrics.TAB_BAR_H) - Host.dp(context, 1).coerceAtLeast(1)))
        labels.forEachIndexed { index, title ->
            val off = ImageView(context).apply {
                setImageResource(offIcons[index])
                setColorFilter(colors.textColorTertiary, PorterDuff.Mode.SRC_IN)
            }
            val on = GradientGlyphView(context, onShapes[index], onDetails[index])
            val label = Host.text(context, title, HostMetrics.TAB_LABEL_SP.toFloat(), colors.textColorTertiary)
            val glyph = FrameLayout(context).apply {
                addView(off, FrameLayout.LayoutParams(-1, -1))
                addView(on, FrameLayout.LayoutParams(-1, -1))
            }
            val iconWrap = FrameLayout(context).apply {
                clipChildren = false
                clipToPadding = false
                addView(glyph, FrameLayout.LayoutParams(Host.dp(context, HostMetrics.TAB_ICON), Host.dp(context, HostMetrics.TAB_ICON), Gravity.CENTER_HORIZONTAL))
                if (index == 1) {
                    badge = Host.badge(context, 0, ringColor = colors.bgColorBottomBar,
                        sizeDp = HostMetrics.TAB_BADGE, textSp = 10f).apply { visibility = GONE }
                    addView(badge, FrameLayout.LayoutParams(-2, -2).apply {
                        topMargin = Host.dp(context, HostMetrics.TAB_BADGE_OFFSET_TOP)
                        leftMargin = Host.dp(context, HostMetrics.TAB_BADGE_OFFSET_LEFT + HostMetrics.TAB_BADGE_ROOM)
                    })
                }
            }
            val column = LinearLayout(context).apply {
                orientation = VERTICAL
                gravity = Gravity.CENTER
                clipChildren = false
                // Symmetric wrapper (glyph + TAB_BADGE_ROOM on both sides): the glyph stays centred above its label
                // and the badge has room on the right. A wrapper that only grew on the badge side pushed the message
                // icon left of its label (iOS keeps the glyph centred).
                addView(iconWrap, LayoutParams(Host.dp(context, HostMetrics.TAB_ICON + 2 * HostMetrics.TAB_BADGE_ROOM), Host.dp(context, HostMetrics.TAB_ICON)))
                addView(label, LayoutParams(-2, -2).apply { topMargin = Host.dp(context, 3) })
                contentDescription = title
                setOnClickListener { onSelect(index) }
            }
            items += Item(off, on, label, column)
            row.addView(column, LayoutParams(0, Host.dp(context, HostMetrics.TAB_ITEM_H), 1f))
        }
        select(0)
    }

    fun select(index: Int) {
        val colors = DemoUi.tokens
        items.forEachIndexed { i, item ->
            val on = i == index
            item.off.visibility = if (on) INVISIBLE else VISIBLE
            item.on.visibility = if (on) VISIBLE else INVISIBLE
            item.label.setTextColor(if (on) colors.textColorLink else colors.textColorTertiary)
            item.label.setTypeface(null, if (on) Typeface.BOLD else Typeface.NORMAL)
            // `.tabbar__item.is-on .ic`: lifted 1px and scaled 1.04.
            (item.off.parent as View).let {
                it.translationY = if (on) -Host.dpf(context, 1f) else 0f
                it.scaleX = if (on) 1.04f else 1f
                it.scaleY = if (on) 1.04f else 1f
            }
        }
    }

    private var badgeCount = 0

    fun setBadge(count: Int) {
        val view = badge ?: return
        val grew = count > badgeCount
        badgeCount = count
        if (count > 0) {
            view.visibility = VISIBLE
            view.text = if (count > 99) "99+" else count.toString()
            if (grew) bounceBadge()
        } else {
            view.visibility = GONE
        }
    }

    fun bounceBadge() {
        val view = badge?.takeIf { it.visibility == VISIBLE } ?: return
        Motion.bump(view)
    }
}

/** Two-tone header glyph: `base` follows textColorPrimary, `accent` follows textColorWarning (sun core, moon star). */
fun twoToneIcon(context: Context, baseRes: Int, accentRes: Int, sizeDp: Int = 24): FrameLayout {
    val c = DemoUi.tokens
    return FrameLayout(context).apply {
        layoutParams = LinearLayout.LayoutParams(Host.dp(context, sizeDp), Host.dp(context, sizeDp))
        addView(ImageView(context).apply {
            setImageResource(baseRes)
            setColorFilter(c.textColorPrimary, PorterDuff.Mode.SRC_IN)
        }, FrameLayout.LayoutParams(-1, -1))
        addView(ImageView(context).apply {
            setImageResource(accentRes)
            setColorFilter(c.textColorWarning, PorterDuff.Mode.SRC_IN)
        }, FrameLayout.LayoutParams(-1, -1))
    }
}

fun sampleAvatar(context: Context, ref: String, name: String, sizeDp: Int): View {
    val frame = FrameLayout(context).apply {
        layoutParams = LinearLayout.LayoutParams(Host.dp(context, sizeDp), Host.dp(context, sizeDp))
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(DemoUi.tokens.bgColorAvatar) }
        Host.circleClip(this)
    }
    val initialsView = Host.text(context, DemoUi.initials(name), sizeDp * 0.4f, DemoUi.tokens.textColorPrimary, bold = true).apply {
        gravity = Gravity.CENTER
    }
    frame.addView(initialsView, FrameLayout.LayoutParams(-1, -1))
    if (ref.isNotBlank()) {
        frame.addView(ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            HostImage.bind(this, ref) { loaded -> initialsView.visibility = if (loaded) View.GONE else View.VISIBLE }
        }, FrameLayout.LayoutParams(-1, -1))
    }
    return frame
}

class SquareFrameLayout(context: Context) : FrameLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, widthMeasureSpec)
    }
}
