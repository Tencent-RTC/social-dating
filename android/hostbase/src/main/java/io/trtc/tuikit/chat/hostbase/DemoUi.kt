package io.trtc.tuikit.chat.hostbase

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens

/** Small shared builders for the demo host. Host colours are read from the current social
 * palette (ThemeStore) on every access, so a palette or light/dark change only needs the
 * activity to be rebuilt (see DemoActivity.onResume).
 */
object DemoUi {
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        (appContext as? android.app.Application)?.let { SocialToast.install(it) }
        io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast.presenter = { text, style, duration ->
            val activity = SocialToast.hasHost()
            if (activity) {
                SocialToast.show(
                    appContext!!, text,
                    when (style) {
                        io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast.Style.SUCCESS -> SocialToast.Kind.SUCCESS
                        io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast.Style.WARNING -> SocialToast.Kind.WARNING
                        io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast.Style.ERROR -> SocialToast.Kind.ERROR
                        else -> SocialToast.Kind.DEFAULT
                    },
                    if (duration == io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast.Duration.LONG) SocialToast.Duration.LONG else SocialToast.Duration.SHORT
                )
            }
            activity
        }
    }

    val tokens: ColorTokens
        get() = ThemeStore.shared(checkNotNull(appContext) { "DemoUi.init must run in Application" })
            .themeState.value.currentTheme.tokens.color

    fun hex(argb: Int): String = String.format("#%08X", argb)

    val BG: String get() = hex(tokens.bgColorDefault)
    val SURFACE: String get() = hex(tokens.bgColorEntryCard)
    val SURFACE_HIGH: String get() = hex(tokens.bgColorFunction)
    val TEXT: String get() = hex(tokens.textColorPrimary)
    val MUTED: String get() = hex(tokens.textColorSecondary)
    val ACCENT: String get() = hex(tokens.buttonColorPrimaryDefault)
    val SUCCESS: String get() = hex(tokens.textColorSuccess)
    /** Selected tab / chip fill, `tabColorSelected`. */
    val SELECTED: String get() = hex(tokens.tabColorSelected)
    val BAR: String get() = hex(tokens.bgColorTopBar)
    val INPUT: String get() = hex(tokens.bgColorInput)

    /** True when the active surface is dark; used for system bar icon colours. */
    val isDark: Boolean
        get() = androidx.core.graphics.ColorUtils.calculateLuminance(tokens.bgColorDefault) < 0.5

    /** Changes whenever palette, mode or resolved colours change; activities rebuild on a diff. */
    fun themeSignature(): String {
        val state = ThemeStore.shared(checkNotNull(appContext)).themeState.value
        return "${state.paletteKey}|${state.currentTheme.id}|${state.currentTheme.tokens.color.bgColorDefault}|${DemoLocale.choice}"
    }

    fun dp(context: Context, value: Int): Int =
        (context.resources.displayMetrics.density * value).toInt()

    fun rounded(color: String, radius: Int, context: Context, stroke: String? = null): GradientDrawable =
        GradientDrawable().apply {
            setColor(Color.parseColor(color))
            cornerRadius = dp(context, radius).toFloat()
            if (stroke != null) setStroke(dp(context, 1), Color.parseColor(stroke))
        }

    fun text(context: Context, value: String, size: Float, color: String = TEXT, bold: Boolean = false) =
        TextView(context).apply {
            text = value
            textSize = size
            setTextColor(Color.parseColor(color))
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }

    fun pill(context: Context, label: String): TextView =
        text(context, label, 11f, MUTED).apply {
            setPadding(dp(context, 9), dp(context, 4), dp(context, 9), dp(context, 4))
            background = rounded(SURFACE_HIGH, 12, context)
        }

    fun initials(name: String): String = name.trim().take(1).ifEmpty { "?" }

    fun avatar(context: Context, name: String, color: String, sizeDp: Int, textSize: Float): TextView =
        text(context, initials(name), textSize, "#FFFFFF", true).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor(color))
            }
            layoutParams = LinearLayout.LayoutParams(dp(context, sizeDp), dp(context, sizeDp))
        }

    fun spacer(context: Context, heightDp: Int): View = View(context).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(context, heightDp))
    }
}
