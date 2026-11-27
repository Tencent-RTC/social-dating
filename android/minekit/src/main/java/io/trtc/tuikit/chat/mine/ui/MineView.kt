package io.trtc.tuikit.chat.mine.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import io.trtc.tuikit.atomicx.theme.Theme
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicxcore.api.login.AllowType
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import io.trtc.tuikit.chat.hostbase.AvatarView
import io.trtc.tuikit.chat.hostbase.DemoLocale
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostImage
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.HostStateView
import io.trtc.tuikit.chat.hostbase.HostThread
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.mine.EditProfileActivity
import io.trtc.tuikit.chat.mine.MineKit
import io.trtc.tuikit.chat.mine.R
import io.trtc.tuikit.chat.mine.data.MineContent
import io.trtc.tuikit.chat.mine.data.MineIdentity
import io.trtc.tuikit.chat.mine.data.MineMenuItem

/**
 * Mine (design B4 `527:2525`): profile card, diamond wallet card, an appearance / language
 * group and a menu group, each block on the list surface with an 8dp background band between them.
 *
 * Exactly three fields are real IM data: avatar, nickname and userID. Everything else (signature,
 * tags, city, wallet, menu values) is loaded from MineKit's MineDataSource and never written back to the SDK.
 * In preview mode (no login) the design sample identity is shown instead so the page can be
 * compared with the design; it is labelled as a preview by the host banner.
 */
class MineView(
    context: Context,
    private val identity: MineIdentity
) : LinearLayout(context) {
    private val tokens get() = DemoUi.tokens
    private val body = LinearLayout(context).apply { orientation = VERTICAL }
    private val state = HostStateView.asContent(context)
    private var alive = true

    init {
        orientation = VERTICAL
        setBackgroundColor(tokens.bgColorTopBar)
        val frame = FrameLayout(context)
        frame.addView(ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
            overScrollMode = OVER_SCROLL_NEVER
            setBackgroundColor(tokens.bgColorDefault)
            addView(body)
        }, FrameLayout.LayoutParams(-1, -1))
        frame.addView(state, FrameLayout.LayoutParams(-1, -1))
        addView(frame, LayoutParams(-1, 0, 1f))
        load()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        alive = false
    }

    private fun load() {
        state.showLoading()
        MineKit.dataSource.loadContent { result ->
            HostThread.runOnMain {
                if (!alive) return@runOnMain
                result.onSuccess {
                    state.hide()
                    render(it)
                }.onFailure { state.showError { load() } }
            }
        }
    }

    private fun render(mine: MineContent) {
        body.removeAllViews()
        val gap = Host.dp(context, HostMetrics.ME_BLOCK_GAP)
        body.addView(block(profileCard(mine)))
        body.addView(block(walletBlock(mine)), blockParams(gap))
        body.addView(block(preferenceGroup()), blockParams(gap))
        mine.menuGroups.forEach { group -> body.addView(block(menuGroup(group)), blockParams(gap)) }
        if (MineKit.actions.isLogoutAvailable()) body.addView(block(logoutRow()), blockParams(gap))
    }

    private fun blockParams(gap: Int) = LayoutParams(-1, -2).apply { topMargin = gap }

    private fun block(child: View) = FrameLayout(context).apply {
        setBackgroundColor(tokens.bgColorTopBar)
        addView(child, FrameLayout.LayoutParams(-1, -2))
    }

    // ------------------------------------------------------------------ profile card

    private fun profileCard(mine: MineContent): View {
        val c = tokens
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        val name = identity.nickname.ifBlank { identity.userId }
        val uid = identity.idText ?: DemoText.get(R.string.demo_id_city, identity.userId, mine.city)
        return LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(pad, pad, pad, pad)
            addView(LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(avatar(name), LayoutParams(Host.dp(context, HostMetrics.ME_AVATAR), Host.dp(context, HostMetrics.ME_AVATAR)).apply {
                    marginEnd = Host.dp(context, 12)
                })
                addView(LinearLayout(context).apply {
                    orientation = VERTICAL
                    addView(Host.text(context, name, 20f, c.textColorPrimary, bold = true, single = true))
                    addView(Host.text(context, uid, 14f, c.textColorSecondary, single = true),
                        LayoutParams(-2, -2).apply { topMargin = Host.dp(context, 4) })
                    addView(LinearLayout(context).apply {
                        orientation = HORIZONTAL
                        mine.tags.forEachIndexed { index, tag ->
                            val view = Host.verifiedTag(context, tag.text)
                            addView(view, LayoutParams(-2, Host.dp(context, 18)).apply {
                                if (index > 0) marginStart = Host.dp(context, 6)
                            })
                        }
                    }, LayoutParams(-2, -2).apply { topMargin = Host.dp(context, 4) })
                }, LayoutParams(0, -2, 1f))
                addView(Host.text(context, mine.editLabel, 14f, c.textColorPrimary).apply {
                    gravity = Gravity.CENTER
                    setPadding(Host.dp(context, 12), 0, Host.dp(context, 12), 0)
                    background = Host.rounded(context, c.bgColorFunction, 16f)
                    contentDescription = mine.editLabel
                    setOnClickListener {
                        if (MineKit.actions.onEditProfileClick(context)) context.startActivity(Intent(context, EditProfileActivity::class.java))
                    }
                }, LayoutParams(-2, Host.dp(context, 32)).apply { marginStart = Host.dp(context, 12) })
            })
            // Real signature once the user has set one; until then the design sample line stays as the placeholder.
            addView(Host.text(context, identity.signature.ifBlank { mine.signature }, 15f, c.textColorSecondary).apply {
                setLineSpacing(Host.dpf(context, 5f), 1f)
            }, LayoutParams(-1, -2).apply { topMargin = Host.dp(context, 12) })
        }
    }

    private fun avatar(name: String): View {
        val size = Host.dp(context, HostMetrics.ME_AVATAR)
        return FrameLayout(context).apply {
            clipChildren = false
            addView(AvatarView(context, name, DemoUi.ACCENT, HostMetrics.ME_AVATAR).also { it.load(identity.avatar) },
                FrameLayout.LayoutParams(size, size))
        }
    }

    // ------------------------------------------------------------------ wallet

    /** `.wallet`: h72 r14, brand glow on the left, 1px primary 22% stroke; balance | promo | 充值. */
    private fun walletBlock(mine: MineContent): View {
        val c = tokens
        val w = mine.wallet
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        val card = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(Host.dp(context, 14), 0, Host.dp(context, 14), 0)
            background = walletBackground()
            contentDescription = "${w.label} ${w.balance}"
            setOnClickListener { MineKit.actions.onWalletClick(context) }
            addView(ImageView(context).apply { setImageResource(R.drawable.demo_me_diamond) },
                LayoutParams(Host.dp(context, 28), Host.dp(context, 28)).apply { marginEnd = Host.dp(context, 10) })
            addView(LinearLayout(context).apply {
                orientation = VERTICAL
                addView(Host.text(context, w.label, 12f, c.textColorTertiary))
                addView(Host.text(context, w.balance, 22f, c.textColorPrimary, bold = true).apply {
                    setPadding(0, Host.dp(context, 1), 0, 0)
                })
            })
            addView(View(context).apply { setBackgroundColor(c.strokeColorPrimary) },
                LayoutParams(Host.dp(context, 1).coerceAtLeast(1), Host.dp(context, 30)).apply {
                    marginStart = Host.dp(context, 12)
                    marginEnd = Host.dp(context, 12)
                })
            addView(LinearLayout(context).apply {
                orientation = VERTICAL
                addView(Host.text(context, w.promo, 11f, c.textColorButton, bold = true).apply {
                    gravity = Gravity.CENTER
                    setPadding(Host.dp(context, 6), 0, Host.dp(context, 6), 0)
                    background = Host.brandGradient(context, 8f)
                }, LayoutParams(-2, Host.dp(context, 16)))
                addView(LinearLayout(context).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(Host.text(context, w.promoPre, 12f, c.textColorSecondary).apply {
                        maxLines = 1
                        ellipsize = android.text.TextUtils.TruncateAt.END
                    }, LayoutParams(0, -2, 1f))
                    addView(ImageView(context).apply { setImageResource(R.drawable.demo_me_diamond_sm) },
                        LayoutParams(Host.dp(context, 14), Host.dp(context, 14)).apply { marginStart = Host.dp(context, 2) })
                    addView(Host.text(context, w.promoBonus, 12f, c.textColorWarning, bold = true).apply { maxLines = 1 },
                        LayoutParams(-2, -2).apply { marginStart = Host.dp(context, 2) })
                }, LayoutParams(-2, -2).apply { topMargin = Host.dp(context, 4) })
            }, LayoutParams(0, -2, 1f))
            addView(Host.text(context, w.action, 14f, c.textColorButton, bold = true).apply {
                gravity = Gravity.CENTER
                setPadding(Host.dp(context, 18), 0, Host.dp(context, 18), 0)
                background = Host.brandGradient(context, 16f)
            }, LayoutParams(-2, Host.dp(context, 32)))
        }
        return FrameLayout(context).apply {
            setPadding(pad, Host.dp(context, 12), pad, Host.dp(context, 12))
            addView(card, FrameLayout.LayoutParams(-1, Host.dp(context, HostMetrics.WALLET_H)))
        }
    }

    private fun walletBackground(): LayerDrawable {
        val c = tokens
        val radius = Host.dpf(context, HostMetrics.WALLET_RADIUS.toFloat())
        val base = GradientDrawable().apply { setColor(c.bgColorOperate); cornerRadius = radius }
        val glow = GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT
            setGradientCenter(0.105f, 0.5f)
            gradientRadius = Host.dpf(context, 90f)
            colors = intArrayOf(Host.alpha(c.buttonColorPrimaryDefault, 0.30f), 0x00000000)
            cornerRadius = radius
        }
        val stroke = GradientDrawable().apply {
            setColor(0x00000000)
            cornerRadius = radius
            setStroke(Host.dp(context, 1).coerceAtLeast(1), Host.alpha(c.buttonColorPrimaryDefault, 0.22f))
        }
        return LayerDrawable(arrayOf(base, glow, stroke))
    }

    // ------------------------------------------------------------------ logout

    /** Full-width row on the list surface; the caption uses the error colour. Confirms before signing out. */
    private fun logoutRow(): View {
        val label = DemoText.get(R.string.demo_log_out)
        return Host.text(context, label, 17f, tokens.textColorError, bold = true).apply {
            gravity = Gravity.CENTER
            contentDescription = label
            isClickable = true
            isFocusable = true
            setOnClickListener { confirmLogout() }
        }.also { it.minimumHeight = Host.dp(context, HostMetrics.MENU_ROW_H) }
    }

    private fun confirmLogout() {
        Host.showThemed(context, android.app.AlertDialog.Builder(context)
            .setTitle(DemoText.get(R.string.demo_log_out_title))
            .setMessage(DemoText.get(R.string.demo_log_out_message))
            .setNegativeButton(DemoText.get(BaseR.string.demo_cancel), null)
            .setPositiveButton(DemoText.get(R.string.demo_log_out)) { _, _ -> MineKit.actions.onLogout(context) })
    }

    // ------------------------------------------------------------------ menu

    private fun menuGroup(group: List<MineMenuItem>): View = rowGroup(group.map { item ->
        MenuRow(item.title, item.icon, item.value) { MineKit.actions.onMenuItemClick(context, item) }
    })

    private class MenuRow(val title: String, val icon: String, var value: String, var onClick: () -> Unit = {}) {
        var valueView: android.widget.TextView? = null
    }

    private fun rowGroup(rows: List<MenuRow>): View {
        val c = tokens
        val pad = Host.dp(context, HostMetrics.SCREEN_PADDING_H)
        return LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(pad, Host.dp(context, 4), pad, Host.dp(context, 4))
            rows.forEach { item ->
                addView(LinearLayout(context).apply {
                    orientation = HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    contentDescription = item.title
                    if (item.icon.isNotBlank()) {
                        addView(ImageView(context).apply { HostImage.bind(this, item.icon) },
                            LayoutParams(Host.dp(context, 24), Host.dp(context, 24)).apply { marginEnd = Host.dp(context, 12) })
                    }
                    addView(Host.text(context, item.title, 17f, c.textColorPrimary), LayoutParams(0, -2, 1f))
                    if (item.value.isNotBlank()) {
                        val valueView = Host.text(context, item.value, 14f, c.textColorTertiary)
                        item.valueView = valueView
                        addView(valueView, LayoutParams(-2, -2).apply { marginEnd = Host.dp(context, 8) })
                    }
                    addView(Host.icon(context, BaseR.drawable.demo_ic_chevron, 12, c.textColorDisable))
                    setOnClickListener { item.onClick() }
                }, LayoutParams(-1, Host.dp(context, HostMetrics.MENU_ROW_H)))
            }
        }
    }

    // ------------------------------------------------------------------ appearance / language

    private fun preferenceGroup(): View {
        val rule = MenuRow(DemoText.get(R.string.demo_friend_add_rule), "", friendAddRuleValue())
        rule.onClick = {
            (context as? Activity)?.let { activity ->
                MineKit.actions.showFriendAddRulePicker(activity) {
                    rule.value = friendAddRuleValue()
                    rule.valueView?.text = rule.value
                }
            }
        }
        return rowGroup(listOf(
            MenuRow(DemoText.get(BaseR.string.demo_appearance), "", appearanceValue()) {
                (context as? Activity)?.let { activity -> MineKit.actions.showAppearancePicker(activity) { activity.recreate() } }
            },
            MenuRow(DemoText.get(BaseR.string.demo_language), "", DemoText.languageName(DemoLocale.choice)) {
                (context as? Activity)?.let { activity -> MineKit.actions.showLanguagePicker(activity) { activity.recreate() } }
            },
            rule
        ))
    }

    /** Who may add me: read from the real IM profile, never from fixtures. */
    private fun friendAddRuleValue(): String = DemoText.get(
        when (LoginStore.shared.loginState.loginUserInfo.value?.allowType) {
            AllowType.ALLOW_ANY -> R.string.demo_allow_any
            AllowType.DENY_ANY -> R.string.demo_deny_any
            else -> R.string.demo_need_confirm
        }
    )

    private fun appearanceValue(): String {
        val store = ThemeStore.shared(context)
        val mode = when (store.themeState.value.currentTheme.id) {
            Theme.LIGHT_THEME_ID -> DemoText.get(BaseR.string.demo_light)
            Theme.DARK_THEME_ID -> DemoText.get(BaseR.string.demo_dark)
            else -> DemoText.get(BaseR.string.demo_follow_system)
        }
        return mode + " · " + DemoText.paletteName(store.currentPaletteKey)
    }
}
