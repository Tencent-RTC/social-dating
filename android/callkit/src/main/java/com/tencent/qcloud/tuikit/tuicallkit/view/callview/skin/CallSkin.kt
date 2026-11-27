package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.content.Context
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.DrawableRes
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicx.theme.tokens.DesignTokenSet
import io.trtc.tuikit.atomicx.theme.palette.SocialPalettes

/**
 * Design S9 / S10 call-page skin helpers.
 *
 * The call page is always rendered with the **dark** tokens of the user's current social palette
 * (design: screen root carries `data-mode="dark"`), regardless of the app-wide light / dark mode.
 * Everything here is code-drawn from tokens; only glyphs are PNG templates tinted at runtime.
 */
object CallSkin {
    fun tokens(context: Context): ColorTokens {
        val key = ThemeStore.shared(context).currentPaletteKey
        return SocialPalettes.apply(DesignTokenSet.defaultDark(context).color, key, true)
    }

    fun dp(context: Context, value: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics).toInt()

    fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb((Color.alpha(color) * alpha).toInt().coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))

    fun oval(color: Int) = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color) }

    /**
     * Resting (off) state of the translucent round call buttons: a deep, mostly opaque scrim plus a thin white
     * rim so the circle still reads on very dark (or very bright) video, instead of the faint `buttonColorOff` wash.
     */
    fun offOval(context: Context) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(OFF_FILL)
        setStroke(dp(context, 1f).coerceAtLeast(1), OFF_RIM)
    }

    const val OFF_FILL = 0xB3101218.toInt()
    const val OFF_RIM = 0x38FFFFFF

    fun rounded(context: Context, color: Int, radiusDp: Float) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(context, radiusDp).toFloat()
        setColor(color)
    }

    /** `brandGradient`: buttonColorPrimaryDefault → tagColorLevel4. */
    fun brandGradient(t: ColorTokens, radiusPx: Float, orientation: GradientDrawable.Orientation = GradientDrawable.Orientation.TL_BR) =
        GradientDrawable(orientation, intArrayOf(t.buttonColorPrimaryDefault, t.tagColorLevel4)).apply { cornerRadius = radiusPx }

    fun icon(context: Context, @DrawableRes res: Int, sizeDp: Float, tint: Int? = null): ImageView =
        ImageView(context).apply {
            setImageResource(res)
            scaleType = ImageView.ScaleType.FIT_CENTER
            layoutParams = LinearLayout.LayoutParams(dp(context, sizeDp), dp(context, sizeDp))
            if (tint != null) colorFilter = PorterDuffColorFilter(tint, PorterDuff.Mode.SRC_IN)
        }

    fun text(context: Context, value: CharSequence, sizeSp: Float, color: Int, bold: Boolean = false) =
        TextView(context).apply {
            text = value
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
            setTextColor(color)
            includeFontPadding = false
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            // Call labels sit on a live camera picture of any brightness; a soft shadow keeps them readable.
            setShadowLayer(dp(context, 2f).toFloat(), 0f, 1f, Color.argb(110, 0, 0, 0))
        }

    /** Press feedback used by every call button (design `:active { transform: scale(.9) }`). */
    fun pressable(view: View, scale: Float = 0.9f, onClick: () -> Unit) {
        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> v.animate().scaleX(scale).scaleY(scale).setDuration(90).start()
                android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL ->
                    v.animate().scaleX(1f).scaleY(1f).setDuration(140).start()
            }
            false
        }
        view.setOnClickListener { onClick() }
    }

    /** Circular 48/52/60 call button: translucent `buttonColorOff`, or white `buttonColorOn` when active. */
    fun circleButton(context: Context, sizeDp: Float, @DrawableRes res: Int, glyphDp: Float, t: ColorTokens, active: Boolean): FrameLayout {
        val box = FrameLayout(context)
        box.layoutParams = LinearLayout.LayoutParams(dp(context, sizeDp), dp(context, sizeDp))
        applyCircleState(box, res, glyphDp, t, active)
        return box
    }

    fun applyCircleState(box: FrameLayout, @DrawableRes res: Int, glyphDp: Float, t: ColorTokens, active: Boolean) {
        box.removeAllViews()
        box.background = if (active) oval(t.buttonColorOn) else offOval(box.context)
        val glyph = icon(box.context, res, glyphDp, if (active) t.bgColorDefault else Color.WHITE)
        glyph.layoutParams = FrameLayout.LayoutParams(dp(box.context, glyphDp), dp(box.context, glyphDp), Gravity.CENTER)
        box.addView(glyph)
    }

    /** 56dp rounded-square gift base: palette gradient + top white highlight + 22% white rim. */
    fun giftBase(context: Context, t: ColorTokens): LayerDrawable {
        val radius = dp(context, 18f).toFloat()
        val base = brandGradient(t, radius).apply { setStroke(dp(context, 1f).coerceAtLeast(1), withAlpha(Color.WHITE, 0.22f)) }
        val highlight = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(withAlpha(Color.WHITE, 0.24f), Color.TRANSPARENT)
        ).apply { cornerRadius = radius }
        return LayerDrawable(arrayOf(base, highlight))
    }

    /**
     * Brand-coloured glow under the gift base (iOS: shadow `tagColorLevel4`, opacity .5, radius 8, offset y 5):
     * a tinted elevation shadow on API 28+, a plain elevation below that.
     */
    fun brandGlow(view: View, t: ColorTokens) {
        view.elevation = dp(view.context, 8f).toFloat()
        view.translationZ = 0f
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            val glow = withAlpha(t.tagColorLevel4, 0.9f)
            view.outlineAmbientShadowColor = glow
            view.outlineSpotShadowColor = glow
        }
    }
}
