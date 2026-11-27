package io.trtc.tuikit.chat.demo.login

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import io.trtc.tuikit.atomicx.theme.Theme
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.palette.SocialPaletteInfo
import io.trtc.tuikit.atomicx.theme.palette.SocialPalettes
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.hostbase.DemoLocale
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.login.AllowType
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import io.trtc.tuikit.atomicxcore.api.login.UserProfile
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.SocialToast

/**
 * Login page bottom sheets (Ardot board K, L4 language / L5 appearance). Both apply the choice
 * immediately and call [onApplied]; the login page then rebuilds itself (and reopens the
 * appearance sheet so several palettes can be compared).
 */
abstract class LoginSheet(context: Context) : Dialog(context) {
    protected val t get() = DemoUi.tokens
    protected val strings = LoginStrings.current()

    protected abstract fun buildContent(content: LinearLayout)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.BOTTOM)
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(0.5f)
        }
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(16) + navigationBarHeight())
            background = GradientDrawable().apply {
                setColor(t.bgColorDialog)
                val r = Host.dpf(context, 24f)
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
                setStroke(dp(1), Host.alpha(Color.WHITE, if (DemoUi.isDark) 0.08f else 0f))
            }
        }
        content.addView(View(context).apply {
            background = Host.rounded(context, Host.alpha(t.textColorTertiary, 0.6f), 2f)
        }, LinearLayout.LayoutParams(dp(36), dp(4)).apply { gravity = Gravity.CENTER_HORIZONTAL })
        buildContent(content)
        setContentView(ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
            addView(content, FrameLayout.LayoutParams(-1, -2))
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        // After setContentView: a floating dialog window otherwise keeps wrap-content width and squeezes the sheet to its handle.
        window?.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
    }

    protected fun title(text: String) = Host.text(context, text, 17f, t.textColorPrimary, bold = true).apply {
        setPadding(dp(8), dp(18), 0, dp(10))
    }

    protected fun label(text: String) = Host.text(context, text, 12f, t.textColorSecondary).apply {
        setPadding(dp(8), dp(12), 0, dp(8))
    }

    protected fun dp(value: Int) = DemoUi.dp(context, value)

    private fun navigationBarHeight(): Int {
        val id = context.resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (id > 0) context.resources.getDimensionPixelSize(id) else 0
    }
}

class LoginLanguageSheet(context: Context, private val onApplied: () -> Unit) : LoginSheet(context) {
    override fun buildContent(content: LinearLayout) {
        content.addView(title(strings.languageTitle))
        val options = listOf(
            DemoLocale.SYSTEM to strings.followSystem,
            DemoLocale.ZH_CN to DemoText.get(BaseR.string.demo_language_zh_hans),
            DemoLocale.ZH_TW to DemoText.get(BaseR.string.demo_language_zh_hant),
            DemoLocale.EN to DemoText.get(BaseR.string.demo_language_english)
        )
        options.forEach { (key, name) ->
            val active = key == DemoLocale.choice
            content.addView(FrameLayout(context).apply {
                isClickable = true
                background = if (active) Host.rounded(context, Host.alpha(t.buttonColorPrimaryDefault, 0.22f), 14f) else null
                setOnClickListener {
                    dismiss()
                    if (!active) {
                        DemoLocale.set(context, key)
                        onApplied()
                    }
                }
                addView(Host.text(context, name, 15f, t.textColorPrimary, bold = active),
                    FrameLayout.LayoutParams(-2, -2, Gravity.CENTER_VERTICAL or Gravity.START).apply { marginStart = dp(12) })
                if (active) {
                    addView(ImageView(context).apply {
                        setImageResource(R.drawable.demo_login_check)
                        setColorFilter(t.buttonColorPrimaryDefault)
                    }, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER_VERTICAL or Gravity.END).apply { marginEnd = dp(14) })
                }
            }, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(2) })
        }
    }
}

class LoginAppearanceSheet(context: Context, private val onApplied: () -> Unit) : LoginSheet(context) {
    private val themeStore by lazy { ThemeStore.shared(context) }

    override fun buildContent(content: LinearLayout) {
        content.addView(title(strings.appearanceTitle))
        content.addView(label(strings.modeTitle))
        content.addView(modeRow())
        content.addView(label(strings.paletteTitle))
        val selected = themeStore.currentPaletteKey
        SocialPalettes.ALL.chunked(4).forEach { rowItems ->
            content.addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                rowItems.forEach { info -> addView(paletteCell(info, info.key == selected), LinearLayout.LayoutParams(0, -2, 1f)) }
            })
        }
    }

    private fun modeRow(): LinearLayout {
        val current = themeStore.themeState.value.currentTheme.id
        val modes = listOf(
            Theme.SYSTEM_THEME_ID to strings.followSystem,
            Theme.LIGHT_THEME_ID to strings.light,
            Theme.DARK_THEME_ID to strings.dark
        )
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            background = Host.rounded(context, t.bgColorInput, 14f)
            setPadding(dp(4), dp(4), dp(4), dp(4))
            modes.forEach { (id, name) ->
                val active = id == current
                addView(Host.text(context, name, 14f, if (active) t.textColorButton else t.textColorPrimary, bold = active).apply {
                    gravity = Gravity.CENTER
                    background = if (active) Host.brandGradient(context, 11f) else null
                    isClickable = true
                    setOnClickListener { chooseMode(id, active) }
                }, LinearLayout.LayoutParams(0, dp(40), 1f))
            }
        }
    }

    private fun chooseMode(id: String, active: Boolean) {
        if (active) return
        val theme = when (id) {
            Theme.LIGHT_THEME_ID -> Theme.lightTheme(context)
            Theme.DARK_THEME_ID -> Theme.darkTheme(context)
            else -> Theme.systemTheme(context)
        }
        themeStore.setTheme(theme)
        dismiss()
        onApplied()
    }

    private fun paletteCell(info: SocialPaletteInfo, active: Boolean): LinearLayout {
        val dark = DemoUi.isDark
        val size = dp(44)
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            contentDescription = DemoText.paletteName(info.key)
            setPadding(0, dp(6), 0, dp(6))
            addView(View(context).apply {
                background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
                    intArrayOf(if (dark) info.gradStart else info.swatchLight, info.gradEnd)).apply {
                    shape = GradientDrawable.OVAL
                    if (active) setStroke(dp(2), t.textColorPrimary)
                }
            }, LinearLayout.LayoutParams(size, size))
            val name = DemoText.paletteName(info.key)
            addView(Host.text(context, name, 11f, if (active) t.textColorPrimary else t.textColorSecondary, bold = active).apply {
                gravity = Gravity.CENTER
                setPadding(0, dp(6), 0, 0)
            })
            setOnClickListener {
                if (!active) {
                    themeStore.setPalette(info.key)
                    dismiss()
                    onApplied()
                }
            }
        }
    }
}

/**
 * Login page copy. The text itself lives in the string resources (`res/values*`, shared keys with iOS);
 * this class only names the entries the login screens use.
 */
class LoginStrings private constructor() {
    val slogan get() = DemoText.get(R.string.demo_1v1_social_chat_meet_the_one)
    val userIdTitle get() = DemoText.get(R.string.demo_user_id)
    val hint get() = DemoText.get(R.string.demo_enter_your_user_id_to_get_started)
    val placeholder get() = DemoText.get(R.string.demo_enter_user_id)
    val login get() = DemoText.get(R.string.demo_log_in)
    val loggingIn get() = DemoText.get(R.string.demo_logging_in)
    val devConfigMissing get() = DemoText.get(R.string.demo_fill_sdkappid_and_secretkey_in_generatetestusersig)
    val signFailed get() = DemoText.get(R.string.demo_local_signing_is_not_configured_check_the)
    fun loginFailed(code: Int) = DemoText.get(R.string.demo_im_login_failed_check_the_account_and, code)
    val callTimeout get() = DemoText.get(R.string.demo_call_component_timed_out_calls_are_unavailable)
    fun callFailed(code: Int) = DemoText.get(R.string.demo_call_init_failed, code)
    val languageTitle get() = DemoText.get(R.string.demo_choose_language)
    val followSystem get() = DemoText.get(BaseR.string.demo_follow_system)
    val languageLabel get() = DemoText.get(BaseR.string.demo_language)
    val appearanceTitle get() = DemoText.get(BaseR.string.demo_appearance)
    val modeTitle get() = DemoText.get(R.string.demo_mode)
    val light get() = DemoText.get(BaseR.string.demo_light)
    val dark get() = DemoText.get(BaseR.string.demo_dark)
    val paletteTitle get() = DemoText.get(R.string.demo_theme_color)
    val appearanceButton get() = appearanceTitle
    val presetAccounts get() = DemoText.get(R.string.demo_preset_accounts)
    val appName get() = DemoText.get(R.string.app_name)

    companion object {
        fun current() = LoginStrings()
    }
}

/**
 * 「我的 → 加好友」bottom sheet: who may add me. Three rules of the IM profile (`allowType`);
 * the choice is written to `LoginStore.setSelfInfo` and the row refreshes through [onApplied].
 */
class FriendAddRuleSheet(context: Context, private val onApplied: () -> Unit) : LoginSheet(context) {
    override fun buildContent(content: LinearLayout) {
        content.addView(title(DemoText.get(R.string.demo_friend_add_rule)))
        val current = LoginStore.shared.loginState.loginUserInfo.value?.allowType ?: AllowType.NEED_CONFIRM
        val options = listOf(
            AllowType.ALLOW_ANY to DemoText.get(R.string.demo_allow_any),
            AllowType.NEED_CONFIRM to DemoText.get(R.string.demo_need_confirm),
            AllowType.DENY_ANY to DemoText.get(R.string.demo_deny_any)
        )
        options.forEach { (type, name) ->
            val active = type == current
            content.addView(FrameLayout(context).apply {
                isClickable = true
                background = if (active) Host.rounded(context, Host.alpha(t.buttonColorPrimaryDefault, 0.22f), 14f) else null
                setOnClickListener {
                    dismiss()
                    if (!active) save(type)
                }
                addView(Host.text(context, name, 15f, t.textColorPrimary, bold = active),
                    FrameLayout.LayoutParams(-2, -2, Gravity.CENTER_VERTICAL or Gravity.START).apply { marginStart = dp(12) })
                if (active) {
                    addView(ImageView(context).apply {
                        setImageResource(R.drawable.demo_login_check)
                        setColorFilter(t.buttonColorPrimaryDefault)
                    }, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER_VERTICAL or Gravity.END).apply { marginEnd = dp(14) })
                }
            }, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(2) })
        }
    }

    private fun save(type: AllowType) {
        val profile = UserProfile().apply { allowType = type }
        LoginStore.shared.setSelfInfo(profile, object : CompletionHandler {
            override fun onSuccess() = onApplied()

            override fun onFailure(code: Int, desc: String) {
                HostDiagnostics.record("mine.friendRule", code, desc)
                SocialToast.show(context, DemoText.get(R.string.demo_setting_update_failed), SocialToast.Kind.ERROR)
            }
        })
    }
}
