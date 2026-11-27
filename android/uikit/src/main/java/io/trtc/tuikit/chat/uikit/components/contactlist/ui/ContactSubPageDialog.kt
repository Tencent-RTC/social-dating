package io.trtc.tuikit.chat.uikit.components.contactlist.ui
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.trtc.tuikit.atomicx.common.util.ScreenUtil.dp2px
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.common.WindowThemeUtil
import io.trtc.tuikit.chat.uikit.components.widgets.DialogNavBar

internal abstract class ContactSubPageDialog(context: Context) : Dialog(context, android.R.style.Theme_NoTitleBar) {

    protected lateinit var rootLayout: LinearLayout
    protected lateinit var contentContainer: FrameLayout
    private lateinit var navBar: DialogNavBar
    private lateinit var dividerView: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)

        val colors = getColors()
        val dm = context.resources.displayMetrics

        rootLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            setBackgroundColor(colors.bgColorTopBar)
            fitsSystemWindows = true
        }

        navBar = DialogNavBar.create(
            context,
            DialogNavBar.Config(
                mode = DialogNavBar.Mode.BackTitle,
                colors = colors,
                onLeadingClick = { dismiss() },
                leadingContentDescription = context.getString(R.string.uikit_back)
            )
        )
        navBar.titleView.textSize = 17f
        navBar.setBackgroundColor(colors.bgColorTopBar)
        rootLayout.addView(navBar)

        dividerView = View(context).apply {
            setBackgroundColor(colors.strokeColorSecondary)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp2px(0.5f, dm).toInt().coerceAtLeast(1)
            )
        }
        rootLayout.addView(dividerView)

        contentContainer = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }
        rootLayout.addView(contentContainer)

        setContentView(rootLayout, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
            addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            WindowThemeUtil.applyDialogSystemBarStyle(this, colors, colors.bgColorTopBar)
        }
    }

    protected fun setTitle(title: String) {
        navBar.setTitle(title)
    }

    protected fun addTrailingAction(view: View) {
        val size = dp2px(TRAILING_ACTION_DP, context.resources.displayMetrics).toInt()
        view.layoutParams = FrameLayout.LayoutParams(size, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.END or Gravity.CENTER_VERTICAL)
        navBar.addView(view)
    }

    protected fun refreshNavBarColors(colors: ColorTokens) {
        rootLayout.setBackgroundColor(colors.bgColorTopBar)
        navBar.applyColors(colors)
        navBar.setBackgroundColor(colors.bgColorTopBar)
        dividerView.setBackgroundColor(colors.strokeColorSecondary)
        window?.let { WindowThemeUtil.applyDialogSystemBarStyle(it, colors, colors.bgColorTopBar) }
    }

    protected fun getColors(): ColorTokens {
        return ThemeStore.shared(context).themeState.value.currentTheme.tokens.color
    }

    private companion object {
        const val TRAILING_ACTION_DP = 44f
    }
}
