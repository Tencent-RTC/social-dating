package io.trtc.tuikit.chat.hostbase

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList
import androidx.annotation.StringRes

/**
 * Host-app copy lookup. Every fixed UI string of the demo host lives in the `res/values` folders (default = English,
 * `values-zh` = Simplified, `values-b+zh+Hant` = Traditional) and is read through here, so the language chosen
 * on the login page ([DemoLocale]) applies to code that has no Activity at hand (toasts, card renderers,
 * summary providers). Customers can translate or reword a string by editing the resource files only.
 *
 * The iOS host uses the same keys in the per-language `Localizable.strings` files under `Resources/Localization`.
 */
object DemoText {
    @Volatile
    private var app: Context? = null

    /** Unit tests have no Android resources; they install a resolver that reads the XML instead. */
    @Volatile
    var resolver: ((Int, Array<out Any?>) -> String)? = null

    @Volatile
    private var cachedTag: String? = null

    @Volatile
    private var cachedContext: Context? = null

    fun init(context: Context) {
        app = context.applicationContext
    }

    fun get(@StringRes id: Int, vararg args: Any?): String {
        resolver?.let { return it(id, args) }
        val context = localizedContext()
        return if (args.isEmpty()) context.getString(id) else context.getString(id, *args)
    }

    /** Display name of a theme palette (`info.key` of the SDK palette table). */
    fun paletteName(key: String): String = byName("demo_palette_$key")

    /** Display name of a language choice of [DemoLocale]. */
    fun languageName(choice: String): String = byName(
        when (choice) {
            DemoLocale.SYSTEM -> "demo_follow_system"
            DemoLocale.ZH_TW -> "demo_language_zh_hant"
            DemoLocale.EN -> "demo_language_english"
            else -> "demo_language_zh_hans"
        }
    )

    /** Resolves a resource by its name; used for the `@demo_...` references inside the app's JSON data. */
    fun byName(name: String): String {
        val context = localizedContext()
        val id = context.resources.getIdentifier(name, "string", context.packageName)
        require(id != 0) { "Missing string resource $name" }
        return context.getString(id)
    }

    private fun localizedContext(): Context {
        val base = checkNotNull(app) { "DemoText.init must be called from Application.onCreate" }
        val locale = DemoLocale.locale
        val tag = locale.toLanguageTag()
        val cached = cachedContext
        if (cached != null && cachedTag == tag) return cached
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        config.setLocales(LocaleList(locale))
        return base.createConfigurationContext(config).also {
            cachedContext = it
            cachedTag = tag
        }
    }

    /** Drops the cached localized context after the language changed. */
    fun invalidate() {
        cachedContext = null
        cachedTag = null
    }
}
