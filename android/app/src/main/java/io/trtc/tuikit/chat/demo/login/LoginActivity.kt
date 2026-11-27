package io.trtc.tuikit.chat.demo.login

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.tencent.cloud.tuikit.engine.call.TUICallEngine
import com.tencent.cloud.tuikit.engine.common.TUICommonDefine
import com.tencent.qcloud.tuikit.tuicallkit.TUICallKit
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.main.MainActivity
import io.trtc.tuikit.chat.hostbase.AvatarView
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import io.trtc.tuikit.chat.hostbase.SocialToast

/** Login entry: only a userID is asked for; language and appearance are changed in place through
 * bottom sheets that rebuild the UI without finishing the activity. The final auth flow matches
 * [GenerateTestUserSig] Debug / Release, no business backend, no welcome message. The last successful login is kept in MMKV and
 * replayed on the next launch; logging out clears it.
 */
class LoginActivity : DemoActivity() {
    override val slideOnStart: Boolean get() = false
    override val slideOnFinish: Boolean get() = false
    private var sdkAppId = 0
    private var userId = ""
    private var userSig = ""
    private var callReady = false
    private var loginInProgress = false
    private var entered = false
    private var resumingLogin = false
    private var silentToken = 0
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    private lateinit var panel: LinearLayout
    private lateinit var column: LinearLayout
    private lateinit var inputFrame: LinearLayout
    private lateinit var userField: EditText
    private lateinit var loginButton: TextView
    private lateinit var userIcon: ImageView
    private lateinit var presetChip: LinearLayout
    private var selectedPreset: PresetAccounts.Entry? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val splash = installSplashScreen()
        super.onCreate(savedInstanceState)
        splash.setKeepOnScreenCondition { resumingLogin }
        val toastPreview = isDebuggable() && intent.getBooleanExtra("toastPreview", false)
        val saved = if (savedInstanceState == null && !toastPreview) savedLoginOrNull() else null
        if (saved != null) {
            resumingLogin = true
            startSilentLogin(saved)
            return
        }
        rebuild()
        if (savedInstanceState == null && toastPreview) playToastPreview()
        if (savedInstanceState == null) {
            intent.getStringExtra(EXTRA_SESSION_NOTICE)?.let { notice ->
                handler.postDelayed({ toast(notice, SocialToast.Kind.ERROR) }, SESSION_NOTICE_DELAY_MS)
            }
        }
    }

    private fun isDebuggable() = applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0

    private fun playToastPreview() {
        val samples = listOf(
            DemoText.get(R.string.demo_scan_demo_placeholder) to SocialToast.Kind.DEFAULT,
            DemoText.get(R.string.demo_profile_saved) to SocialToast.Kind.SUCCESS,
            DemoText.get(R.string.demo_preview_mode_not_logged_in_cannot_open) to SocialToast.Kind.WARNING,
            DemoText.get(R.string.demo_log_out_failed) to SocialToast.Kind.ERROR
        )
        samples.forEachIndexed { index, sample ->
            handler.postDelayed({ toast(sample.first, sample.second) }, 1500L + index * 3000L)
        }
    }

    private fun savedLoginOrNull(): SavedLogin? {
        val saved = DemoLoginStore.load() ?: return null
        if (!GenerateTestUserSig.isConfigured) return null
        if (saved.sdkAppId != GenerateTestUserSig.SDKAPPID) {
            DemoLoginStore.clear()
            return null
        }
        return saved
    }

    private fun startSilentLogin(saved: SavedLogin) {
        val ticket = runCatching { GenerateTestUserSig.genTicket(saved.userId) }.getOrNull()
        if (ticket == null) {
            HostDiagnostics.record("login.silent", 0, "local signing failed")
            return abortSilentLogin(LoginStrings.current().signFailed)
        }
        sdkAppId = ticket.sdkAppId
        userId = ticket.userId
        userSig = ticket.userSig
        val token = ++silentToken
        handler.postDelayed({
            if (resumingLogin && token == silentToken) {
                HostDiagnostics.record("login.silent", 0, "timed out")
                abortSilentLogin(DemoText.get(R.string.demo_login_timed_out))
            }
        }, SILENT_LOGIN_TIMEOUT_MS)
        io.trtc.tuikit.atomicxcore.api.login.LoginStore.shared.login(
            this, sdkAppId, userId, userSig,
            object : CompletionHandler {
                override fun onSuccess() = runOnUiThread {
                    if (isFinishing || isDestroyed || !resumingLogin || token != silentToken) return@runOnUiThread
                    DemoLoginStore.save(sdkAppId, userId)
                    initCall()
                }

                override fun onFailure(code: Int, desc: String) = runOnUiThread {
                    if (isFinishing || isDestroyed || !resumingLogin || token != silentToken) return@runOnUiThread
                    HostDiagnostics.record("login.silent", code, desc)
                    abortSilentLogin(LoginStrings.current().loginFailed(code))
                }
            }
        )
    }

    private fun abortSilentLogin(message: String) {
        silentToken++
        userSig = ""
        handler.removeCallbacksAndMessages(null)
        resumingLogin = false
        rebuild()
        toast(message, SocialToast.Kind.ERROR)
    }

    /** Rebuilds the entire content with the current locale and palette, called after sheet changes. */
    private fun rebuild() {
        themeSignature = DemoUi.themeSignature()
        val strings = LoginStrings.current()
        val tokens = DemoUi.tokens
        @Suppress("DEPRECATION")
        window.statusBarColor = tokens.bgColorDefault
        @Suppress("DEPRECATION")
        window.navigationBarColor = tokens.bgColorDefault

        val root = FrameLayout(this).apply {
            setBackgroundColor(tokens.bgColorDefault)
            clipChildren = true
        }
        val dark = DemoUi.isDark
        root.addView(glow(460, tokens.buttonColorPrimaryDefault, if (dark) 0.62f else 0.32f, Gravity.TOP or Gravity.START, -110, -150))
        root.addView(glow(360, tokens.tagColorLevel4, if (dark) 0.46f else 0.26f, Gravity.TOP or Gravity.END, 120, -20))
        root.addView(glow(520, tokens.buttonColorPrimaryDefault, if (dark) 0.22f else 0.12f, Gravity.BOTTOM or Gravity.START, -80, 200))

        column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            clipChildren = false
        }
        column.addView(logoZone(), LinearLayout.LayoutParams(-1, dp(106)))
        column.addView(Host.text(this, DemoText.get(R.string.app_name), 34f, tokens.textColorPrimary, bold = true),
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(20) })
        column.addView(Host.text(this, strings.slogan, 14f, tokens.textColorSecondary),
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(6) })
        panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(24), dp(22), dp(22))
            background = GradientDrawable().apply {
                cornerRadius = Host.dpf(this@LoginActivity, 26f)
                setColor(if (dark) Host.alpha(tokens.bgColorOperate, 0.86f) else Host.alpha(tokens.bgColorDialog, 0.92f))
                setStroke(dp(1), if (dark) Host.alpha(Color.WHITE, 0.10f) else tokens.strokeColorPrimary)
            }
        }
        column.addView(panel, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(48)
            marginStart = dp(20)
            marginEnd = dp(20)
        })
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            addView(column, FrameLayout.LayoutParams(-1, -2))
        }
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        val entries = topEntries(strings, tokens)
        root.addView(entries, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.END).apply {
            marginEnd = dp(16)
            topMargin = dp(8)
        })
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            column.setPadding(0, bars.top + dp(74), 0, maxOf(bars.bottom, ime.bottom) + dp(24))
            (entries.layoutParams as FrameLayout.LayoutParams).topMargin = bars.top + dp(8)
            entries.requestLayout()
            insets
        }
        // A rebuild (language / appearance change) gets no fresh insets dispatch, so ask for one explicitly.
        ViewCompat.requestApplyInsets(root)
        showLogin()
    }

    /** Top-right pair of round glass buttons (design L1): translate = language, palette = appearance. */
    private fun topEntries(strings: LoginStrings, tokens: ColorTokens): LinearLayout {
        val dark = DemoUi.isDark
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            fun iconButton(icon: Int, label: String, last: Boolean, action: () -> Unit) = FrameLayout(this@LoginActivity).apply {
                isClickable = true
                isFocusable = true
                contentDescription = label
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(if (dark) Host.alpha(Color.WHITE, 0.08f) else Host.alpha(Color.WHITE, 0.72f))
                    setStroke(dp(1), if (dark) Host.alpha(Color.WHITE, 0.16f) else tokens.strokeColorPrimary)
                }
                setOnClickListener { action() }
                addView(ImageView(this@LoginActivity).apply {
                    setImageResource(icon)
                    setColorFilter(tokens.textColorPrimary)
                }, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
                layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply { if (!last) marginEnd = dp(8) }
            }
            addView(iconButton(R.drawable.demo_login_globe, strings.languageLabel, false) { showLanguageSheet() })
            addView(iconButton(R.drawable.demo_login_palette, strings.appearanceButton, true) { showAppearanceSheet() })
        }
    }

    private fun showLanguageSheet() = LoginLanguageSheet(this) { rebuild() }.show()
    private fun showAppearanceSheet() = LoginAppearanceSheet(this) { rebuild() }.show()

    /** Design L1: soft radial light behind the hero (brand violet / pink); positions follow the 360dp frame. */
    private fun glow(size: Int, color: Int, alpha: Float, gravity: Int, x: Int, y: Int): View = View(this).apply {
        background = GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT
            gradientRadius = dp(size) / 2f
            colors = intArrayOf(Host.alpha(color, alpha), Host.alpha(color, 0f))
        }
        layoutParams = FrameLayout.LayoutParams(dp(size), dp(size), gravity)
        translationX = dp(x).toFloat()
        translationY = dp(y).toFloat()
    }

    /** 96dp gradient logo tile with the bubble + heart glyph, and three twinkles around it (10dp headroom for the stars). */
    private fun logoZone(): View {
        val tokens = DemoUi.tokens
        val dark = DemoUi.isDark
        val zone = FrameLayout(this).apply { clipChildren = false }
        val logo = FrameLayout(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(tokens.buttonColorPrimaryDefault, tokens.tagColorLevel4)
            ).apply {
                cornerRadius = Host.dpf(this@LoginActivity, 26f)
                setStroke(dp(1), Host.alpha(Color.WHITE, 0.28f))
            }
            elevation = Host.dpf(this@LoginActivity, 14f)
            if (android.os.Build.VERSION.SDK_INT >= 28) {
                outlineSpotShadowColor = Host.alpha(tokens.tagColorLevel4, 0.9f)
            }
            addView(ImageView(context).apply {
                setImageResource(R.drawable.demo_login_glyph)
                scaleType = ImageView.ScaleType.FIT_XY
            }, FrameLayout.LayoutParams(-1, -1))
        }
        zone.addView(logo, FrameLayout.LayoutParams(dp(96), dp(96), Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(10) })
        fun star(res: Int, size: Int, dx: Int, dy: Int, tint: Int, alpha: Float) {
            zone.addView(ImageView(this).apply {
                setImageResource(res)
                setColorFilter(tint)
                this.alpha = alpha
            }, FrameLayout.LayoutParams(dp(size), dp(size), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                leftMargin = dp(dx)
                topMargin = dp(dy)
            })
        }
        star(R.drawable.demo_login_star_big, 22, 93, 0, if (dark) Color.WHITE else tokens.buttonColorPrimaryDefault, if (dark) 0.85f else 0.9f)
        star(R.drawable.demo_login_star_small, 10, 113, 38, if (dark) Color.WHITE else tokens.tagColorLevel4, if (dark) 0.6f else 0.8f)
        star(R.drawable.demo_login_star_left, 12, -112, 78, if (dark) Color.WHITE else tokens.buttonColorPrimaryDefault, if (dark) 0.5f else 0.8f)
        return zone
    }

    private fun showLogin() {
        val tokens = DemoUi.tokens
        val strings = LoginStrings.current()
        panel.removeAllViews()
        if (!GenerateTestUserSig.isConfigured) {
            panel.addView(Host.text(this, strings.devConfigMissing, 15f, tokens.textColorSecondary))
            return
        }
        panel.addView(Host.text(this, strings.userIdTitle, 15f, tokens.textColorPrimary, bold = true))
        panel.addView(Host.text(this, strings.hint, 12f, tokens.textColorSecondary),
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(16) })

        userField = EditText(this).apply {
            hint = strings.placeholder
            setHintTextColor(tokens.textColorTertiary)
            setTextColor(tokens.textColorPrimary)
            textSize = 16f
            isSingleLine = true
            maxLines = 1
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            imeOptions = EditorInfo.IME_ACTION_DONE
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            isSaveEnabled = false
            gravity = Gravity.CENTER_VERTICAL
            background = null
            setPadding(0, 0, 0, 0)
        }
        userIcon = ImageView(this).apply {
            setImageResource(R.drawable.demo_login_user)
            setColorFilter(tokens.textColorSecondary)
        }
        presetChip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            isClickable = true
            isFocusable = true
            setOnClickListener { editSelectedPreset() }
        }
        inputFrame = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), 0, dp(16), 0)
            addView(userIcon, LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(10) })
            addView(presetChip, LinearLayout.LayoutParams(0, -1, 1f))
            addView(userField, LinearLayout.LayoutParams(0, -1, 1f))
            addView(ImageView(context).apply {
                setImageResource(R.drawable.demo_login_chevron_down)
                setColorFilter(tokens.textColorSecondary)
                setPadding(dp(6), dp(6), dp(6), dp(6))
                contentDescription = strings.presetAccounts
                isClickable = true
                isFocusable = true
                setOnClickListener { showPresetMenu() }
            }, LinearLayout.LayoutParams(dp(32), dp(32)).apply { marginStart = dp(4) })
        }
        styleInput(false)
        panel.addView(inputFrame, LinearLayout.LayoutParams(-1, dp(52)).apply { topMargin = dp(16) })

        loginButton = TextView(this).apply {
            text = strings.login
            textSize = 17f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            background = buttonBackground()
            setTextColor(android.content.res.ColorStateList(
                arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
                intArrayOf(tokens.textColorButtonDisabled, tokens.textColorButton)
            ))
            setOnClickListener { submit() }
        }
        panel.addView(loginButton, LinearLayout.LayoutParams(-1, dp(52)).apply { topMargin = dp(16) })

        userField.setOnFocusChangeListener { _, focused -> styleInput(focused) }
        userField.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = updateButton(s?.toString().orEmpty())
            override fun afterTextChanged(s: Editable?) {}
        })
        userField.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE && loginButton.isEnabled) {
                submit()
                true
            } else {
                false
            }
        }
        val last = DemoLoginStore.load()?.userId.orEmpty()
        userField.setText(last)
        userField.setSelection(userField.text.length)
        updateButton(last)
        selectedPreset?.let { showPresetChip(it) }
    }

    /** Shows the chosen preset (avatar, nickname, userID) inside the input; the field keeps the userID for the login button. */
    private fun showPresetChip(entry: PresetAccounts.Entry) {
        val tokens = DemoUi.tokens
        selectedPreset = entry
        userField.setText(entry.userId)
        userField.setSelection(userField.text.length)
        presetChip.removeAllViews()
        presetChip.contentDescription = "${entry.name} ${entry.userId}"
        presetChip.addView(AvatarView(this, entry.name, sizeDp = 32).apply { load(entry.avatarUrl) })
        presetChip.addView(Host.text(this, entry.name, 15f, tokens.textColorPrimary, bold = true).apply {
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(10) })
        presetChip.addView(Host.text(this, entry.userId, 12f, tokens.textColorSecondary).apply {
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(8) })
        userIcon.visibility = View.GONE
        userField.visibility = View.GONE
        presetChip.visibility = View.VISIBLE
        updateButton(entry.userId)
    }

    private fun showTypedInput() {
        presetChip.visibility = View.GONE
        userIcon.visibility = View.VISIBLE
        userField.visibility = View.VISIBLE
    }

    /** Tapping the chip drops back to plain text editing with the userID in place. */
    private fun editSelectedPreset() {
        if (loginInProgress) return
        selectedPreset = null
        showTypedInput()
        userField.requestFocus()
        userField.setSelection(userField.text.length)
        (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager)
            .showSoftInput(userField, 0)
    }

    /** Dropdown under the input: choosing a preset account only fills the input; signing in waits for the login button. */
    private fun showPresetMenu() {
        if (loginInProgress) return
        val tokens = DemoUi.tokens
        val strings = LoginStrings.current()
        val dark = DemoUi.isDark
        (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager)
            .hideSoftInputFromWindow(userField.windowToken, 0)
        val menu = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(4), dp(8), dp(4), dp(8))
            elevation = Host.dpf(this@LoginActivity, 8f)
            background = GradientDrawable().apply {
                cornerRadius = Host.dpf(this@LoginActivity, 14f)
                setColor(if (dark) tokens.bgColorOperate else tokens.bgColorDialog)
                setStroke(dp(1), if (dark) Host.alpha(Color.WHITE, 0.10f) else tokens.strokeColorPrimary)
            }
        }
        val popup = android.widget.PopupWindow(menu, inputFrame.width, -2, true).apply {
            isOutsideTouchable = true
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
            elevation = Host.dpf(this@LoginActivity, 8f)
        }
        menu.addView(Host.text(this, strings.presetAccounts, 12f, tokens.textColorSecondary),
            LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(12); bottomMargin = dp(4) })
        for (entry in PresetAccounts.load(this)) {
            val name = entry.name
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(12), dp(6), dp(12), dp(6))
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    popup.dismiss()
                    showPresetChip(entry)
                }
            }
            row.addView(AvatarView(this, name, sizeDp = 36).apply { load(entry.avatarUrl) })
            row.addView(Host.text(this, name, 15f, tokens.textColorPrimary, bold = true),
                LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(10) })
            row.addView(Host.text(this, entry.userId, 12f, tokens.textColorSecondary),
                LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(10) })
            menu.addView(row, LinearLayout.LayoutParams(-1, -2))
        }
        menu.measure(
            android.view.View.MeasureSpec.makeMeasureSpec(inputFrame.width, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED)
        )
        val anchor = IntArray(2).also { inputFrame.getLocationOnScreen(it) }
        val below = resources.displayMetrics.heightPixels - (anchor[1] + inputFrame.height) - dp(6)
        if (menu.measuredHeight > below) {
            popup.showAsDropDown(inputFrame, 0, -(inputFrame.height + menu.measuredHeight + dp(6)))
        } else {
            popup.showAsDropDown(inputFrame, 0, dp(6))
        }
    }

    /** Design L2: the focused field gets a brand-violet 1.5dp outline. */
    private fun styleInput(focused: Boolean) {
        val tokens = DemoUi.tokens
        inputFrame.background = GradientDrawable().apply {
            cornerRadius = Host.dpf(this@LoginActivity, 14f)
            setColor(tokens.bgColorInput)
            if (focused) setStroke(Host.dp(this@LoginActivity, 2) * 3 / 4, tokens.buttonColorPrimaryDefault)
            else setStroke(dp(1), tokens.strokeColorPrimary)
        }
    }

    private fun buttonBackground(): StateListDrawable {
        val tokens = DemoUi.tokens
        fun gradient(start: Int) = GradientDrawable(
            GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, tokens.tagColorLevel4)
        ).apply { cornerRadius = Host.dpf(this@LoginActivity, 26f) }
        return StateListDrawable().apply {
            addState(intArrayOf(-android.R.attr.state_enabled), GradientDrawable().apply {
                setColor(tokens.buttonColorPrimaryDisabled)
                cornerRadius = Host.dpf(this@LoginActivity, 26f)
            })
            addState(intArrayOf(android.R.attr.state_pressed), gradient(tokens.buttonColorPrimaryActive))
            addState(intArrayOf(), gradient(tokens.buttonColorPrimaryDefault))
        }
    }

    private fun updateButton(input: String) {
        loginButton.isEnabled = input.trim().isNotEmpty() && !loginInProgress
    }

    private fun submit() {
        if (loginInProgress) return
        val enteredUserId = userField.text.toString().trim()
        if (enteredUserId.isEmpty()) return
        val ticket = runCatching { GenerateTestUserSig.genTicket(enteredUserId) }.getOrNull()
        if (ticket == null) {
            toast(LoginStrings.current().signFailed, SocialToast.Kind.ERROR)
            return
        }
        sdkAppId = ticket.sdkAppId
        userId = ticket.userId
        userSig = ticket.userSig
        loginInProgress = true
        loginButton.isEnabled = false
        loginButton.text = LoginStrings.current().loggingIn
        io.trtc.tuikit.atomicxcore.api.login.LoginStore.shared.login(
            this, sdkAppId, userId, userSig,
            object : CompletionHandler {
                override fun onSuccess() = runOnUiThread {
                    if (!isFinishing && !isDestroyed) {
                        loginInProgress = false
                        DemoLoginStore.save(sdkAppId, userId)
                        initCall()
                    }
                }

                override fun onFailure(code: Int, desc: String) = runOnUiThread {
                    loginInProgress = false
                    userSig = ""
                    if (!isFinishing && !isDestroyed) {
                        loginButton.text = LoginStrings.current().login
                        updateButton(userField.text.toString())
                        toast(LoginStrings.current().loginFailed(code), SocialToast.Kind.ERROR)
                    }
                }
            }
        )
    }

    private fun initCall() {
        handler.postDelayed({
            if (!entered && !isFinishing && !isDestroyed) {
                userSig = ""
                callReady = false
                toast(LoginStrings.current().callTimeout, SocialToast.Kind.WARNING)
                showEntries()
            }
        }, CALL_INIT_TIMEOUT_MS)
        TUICallEngine.createInstance(this).init(sdkAppId, userId, userSig, object : TUICommonDefine.Callback {
            override fun onSuccess() = runOnUiThread {
                userSig = ""
                callReady = true
                // CallKit follows LoginStore by itself: it creates TUICallKit (incoming-call observers)
                // as soon as LoginStore reports LOGINED, and sets up the notification channel, ringtone
                // and vibration once per process. The app only initializes the engine, since only it
                // holds the userSig; the createInstance below is an idempotent fallback. The incoming
                // banner stays off, so an incoming call opens the full-screen call page directly (same
                // as iOS).
                TUICallKit.createInstance(applicationContext)
                enableCallMultiDevice()
                showEntries()
            }
            override fun onError(errCode: Int, errMsg: String) = runOnUiThread {
                userSig = ""
                callReady = false
                toast(LoginStrings.current().callFailed(errCode), SocialToast.Kind.ERROR)
                showEntries()
            }
        })
    }

    private fun showEntries() {
        if (entered) return
        entered = true
        handler.removeCallbacksAndMessages(null)
        startActivity(Intent(this, MainActivity::class.java)
            .putExtra("userId", userId)
            .putExtra("callReady", callReady))
        finish()
    }

    private fun enableCallMultiDevice() {
        TUICallEngine.createInstance(applicationContext).enableMultiDeviceAbility(true,
            object : TUICommonDefine.Callback {
                override fun onSuccess() {
                    HostDiagnostics.record("call.multiDevice", message = "enabled")
                }

                override fun onError(errCode: Int, errMsg: String?) {
                    HostDiagnostics.record("call.multiDevice", code = errCode, message = errMsg.orEmpty())
                }
            })
    }

    private fun dp(value: Int) = (resources.displayMetrics.density * value).toInt()
    private fun toast(text: String, kind: SocialToast.Kind = SocialToast.Kind.DEFAULT) =
        SocialToast.show(this, text, kind, SocialToast.Duration.LONG)

    companion object {
        const val EXTRA_SESSION_NOTICE = "sessionNotice"
        private const val SESSION_NOTICE_DELAY_MS = 350L
        private const val CALL_INIT_TIMEOUT_MS = 8000L
        private const val SILENT_LOGIN_TIMEOUT_MS = 10000L
    }
}
