package io.trtc.tuikit.chat.hostbase

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import androidx.appcompat.app.AppCompatActivity
import java.util.Locale

/**
 * Demo locale: the V2 prototype and host copy are Simplified Chinese, so that stays the default
 * and SDK strings (input placeholder, menus, empty states) resolve to `values-zh`. The login page
 * can switch to Traditional Chinese, English or follow the system; the choice is stored locally.
 * Only the login page host copy is translated so far, other host screens stay Chinese.
 *
 * `AppCompatDelegate.setApplicationLocales` is a no-op when called from
 * `Application.onCreate` on API 33+ (no activity delegate yet), so the locale is
 * applied to every context directly instead. Customers can delete this file and
 * the `DemoActivity` base class to fall back to the system language.
 */
object DemoLocale {
    const val SYSTEM = "system"
    const val ZH_CN = "zh-CN"
    const val ZH_TW = "zh-TW"
    const val EN = "en"
    private const val PREFS = "demo_locale"
    private const val KEY = "choice"

    @Volatile
    private var loaded = false

    @Volatile
    var choice: String = ZH_CN
        private set

    val locale: Locale
        get() = when (choice) {
            ZH_TW -> Locale.TRADITIONAL_CHINESE
            EN -> Locale.ENGLISH
            SYSTEM -> android.content.res.Resources.getSystem().configuration.locales[0]
            else -> Locale.SIMPLIFIED_CHINESE
        }

    /** Display language of the host copy: "zh", "zh-TW" or "en" (any other system language falls back to English). */
    val language: String
        get() = locale.let {
            when {
                it.language == "zh" && (it.country in setOf("TW", "HK", "MO") || it.script == "Hant") -> ZH_TW
                it.language == "zh" -> ZH_CN
                else -> EN
            }
        }

    private fun load(context: Context) {
        if (loaded) return
        choice = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, ZH_CN) ?: ZH_CN
        loaded = true
    }

    /** Stores [value]; activities pick it up when they are recreated, the application context is refreshed best-effort. */
    fun set(context: Context, value: String) {
        choice = value
        loaded = true
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, value).apply()
        runCatching {
            val app = context.applicationContext
            val config = Configuration(app.resources.configuration)
            config.setLocale(locale)
            config.setLocales(LocaleList(locale))
            Locale.setDefault(locale)
            @Suppress("DEPRECATION")
            app.resources.updateConfiguration(config, app.resources.displayMetrics)
        }
    }

    fun wrap(base: Context): Context {
        load(base)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        config.setLocales(LocaleList(locale))
        Locale.setDefault(locale)
        return base.createConfigurationContext(config)
    }
}

/**
 * Base class for every demo screen: locale lock plus brand-dark system bars, so
 * the status/navigation bar areas never show the light window default.
 */
open class DemoActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(DemoLocale.wrap(newBase))
    }

    protected open val slideOnStart: Boolean get() = true

    protected open val slideOnFinish: Boolean get() = true

    override fun startActivity(intent: android.content.Intent?, options: android.os.Bundle?) {
        super.startActivity(intent, options)
        if (slideOnStart && options == null && Motion.enabled(this)) {
            @Suppress("DEPRECATION")
            overridePendingTransition(R.anim.host_push_in, R.anim.host_push_out)
        }
    }

    override fun finish() {
        super.finish()
        if (slideOnFinish && Motion.enabled(this)) {
            @Suppress("DEPRECATION")
            overridePendingTransition(R.anim.host_pop_in, R.anim.host_pop_out)
        }
    }

    protected var themeSignature: String = ""

    /**
     * Immersive page: the root pads itself by the system bars, and the strip behind the status bar is painted with the
     * colour of the title bar underneath ([topColor]) so both read as one bar. Android 15 ignores
     * `window.statusBarColor`, so the colour has to come from the page itself.
     */
    protected fun immersive(root: android.view.View, topColor: Int, bodyColor: Int = android.graphics.Color.parseColor(io.trtc.tuikit.chat.hostbase.DemoUi.BG),
                            bottomColor: Int = topColor,
                            extra: (androidx.core.graphics.Insets, androidx.core.view.WindowInsetsCompat) -> Unit = { _, _ -> }) {
        val background = StatusBarBackground(topColor, bodyColor, bottomColor)
        root.background = background
        @Suppress("DEPRECATION")
        window.statusBarColor = topColor
        @Suppress("DEPRECATION")
        window.navigationBarColor = bottomColor
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            background.topHeight = bars.top
            background.bottomHeight = bars.bottom
            extra(bars, insets)
            insets
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val ui = io.trtc.tuikit.chat.hostbase.DemoUi
        themeSignature = ui.themeSignature()
        val background = android.graphics.Color.parseColor(ui.BG)
        window.decorView.setBackgroundColor(background)
        @Suppress("DEPRECATION")
        window.statusBarColor = android.graphics.Color.parseColor(ui.BAR)
        @Suppress("DEPRECATION")
        window.navigationBarColor = background
        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = !ui.isDark
            isAppearanceLightNavigationBars = !ui.isDark
        }
    }

    override fun onResume() {
        super.onResume()
        // Palette / mode changed while this screen was in the back stack: rebuild with new colours.
        if (themeSignature.isNotEmpty() && themeSignature != io.trtc.tuikit.chat.hostbase.DemoUi.themeSignature()) {
            recreate()
        }
    }
}

/** Body colour everywhere, with the status-bar strip in [topColor] and the navigation-bar strip in [bottomColor]. */
class StatusBarBackground(private val topColor: Int, private val bodyColor: Int, private val bottomColor: Int = topColor) : android.graphics.drawable.Drawable() {
    var topHeight = 0
        set(value) {
            field = value
            invalidateSelf()
        }
    var bottomHeight = 0
        set(value) {
            field = value
            invalidateSelf()
        }
    private val paint = android.graphics.Paint()

    override fun draw(canvas: android.graphics.Canvas) {
        paint.color = bodyColor
        canvas.drawRect(bounds, paint)
        paint.color = topColor
        canvas.drawRect(bounds.left.toFloat(), bounds.top.toFloat(), bounds.right.toFloat(), (bounds.top + topHeight).toFloat(), paint)
        paint.color = bottomColor
        canvas.drawRect(bounds.left.toFloat(), (bounds.bottom - bottomHeight).toFloat(), bounds.right.toFloat(), bounds.bottom.toFloat(), paint)
    }

    override fun setAlpha(alpha: Int) = Unit
    override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) = Unit
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = android.graphics.PixelFormat.OPAQUE
}
