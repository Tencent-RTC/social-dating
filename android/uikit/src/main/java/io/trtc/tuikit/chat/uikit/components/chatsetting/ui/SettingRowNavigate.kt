package io.trtc.tuikit.chat.uikit.components.chatsetting.ui
import android.content.Context
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.atomicx.common.util.ScreenUtil.dp2px
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class SettingRowNavigate @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : LinearLayout(context, attrs, defStyleAttr) {

    private val titleTextView: TextView
    private val valueTextView: TextView
    private val accessoryImageView: ImageView
    private val badgeTextView: TextView
    private var danger = false
    private var viewScope: CoroutineScope? = null
    private var showArrow: Boolean = true
    private var customAccessoryResId: Int? = null

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        layoutDirection = LAYOUT_DIRECTION_LOCALE
        val horizontalPadding = dp2px(16f, resources.displayMetrics).toInt()
        val verticalPadding = dp2px(8f, resources.displayMetrics).toInt()
        setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
        setMinimumHeight(dp2px(ChatSettingSceneSpec.ROW_MIN_HEIGHT_DP.toFloat(), resources.displayMetrics).toInt())
        isClickable = true
        isFocusable = true

        titleTextView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ChatSettingSceneSpec.LABEL_SP.toFloat())
            textAlignment = View.TEXT_ALIGNMENT_VIEW_START
            textDirection = View.TEXT_DIRECTION_LOCALE
            maxLines = 1
        }
        addView(titleTextView, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))

        // Right group (prototype `.setrow__right`): badge, value, chevron.
        badgeTextView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER
            val pad = dp2px(6f, resources.displayMetrics).toInt()
            setPadding(pad, dp2px(1f, resources.displayMetrics).toInt(), pad, dp2px(1f, resources.displayMetrics).toInt())
            visibility = GONE
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp2px(ChatSettingSceneSpec.ROW_GAP_DP.toFloat(), resources.displayMetrics).toInt()
            }
        }
        addView(badgeTextView)

        valueTextView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ChatSettingSceneSpec.VALUE_SP.toFloat())
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            textAlignment = View.TEXT_ALIGNMENT_VIEW_END
            textDirection = View.TEXT_DIRECTION_LOCALE
            maxLines = 1
            maxWidth = dp2px(180f, resources.displayMetrics).toInt()
            ellipsize = android.text.TextUtils.TruncateAt.END
            visibility = GONE
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp2px(ChatSettingSceneSpec.ROW_GAP_DP.toFloat(), resources.displayMetrics).toInt()
            }
        }
        addView(valueTextView)

        accessoryImageView = ImageView(context).apply {
            layoutDirection = LAYOUT_DIRECTION_LOCALE
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            layoutParams = LayoutParams(
                dp2px(ChatSettingSceneSpec.CHEVRON_DP.toFloat(), resources.displayMetrics).toInt(),
                dp2px(ChatSettingSceneSpec.CHEVRON_DP.toFloat(), resources.displayMetrics).toInt()
            ).apply {
                marginStart = dp2px(ChatSettingSceneSpec.ROW_GAP_DP.toFloat(), resources.displayMetrics).toInt()
            }
        }
        addView(accessoryImageView)
    }

    fun setTitle(title: String) {
        titleTextView.text = title
    }

    fun setValue(value: String) {
        valueTextView.text = value
        valueTextView.visibility = if (value.isEmpty()) GONE else VISIBLE
    }

    /** Level-style capsule on the right (prototype `.tag--level`), e.g. "Lv.3". */
    fun setBadge(text: String?) {
        badgeTextView.text = text.orEmpty()
        badgeTextView.visibility = if (text.isNullOrEmpty()) GONE else VISIBLE
    }

    /** Danger style (prototype `.setrow--danger`): label in error colour, chevron at 60%. */
    fun setDanger(isDanger: Boolean) {
        danger = isDanger
        applyThemeColors(getColors())
    }

    fun setShowArrow(show: Boolean) {
        showArrow = show
        applyAccessory(getColors())
    }

    fun setCustomAccessory(drawableResId: Int?) {
        customAccessoryResId = drawableResId
        applyAccessory(getColors())
    }

    private fun applyThemeColors(colors: ColorTokens) {
        setBackgroundColor(colors.bgColorOperate)
        titleTextView.setTextColor(if (danger) colors.textColorError else colors.textColorPrimary)
        valueTextView.setTextColor(colors.textColorSecondary)
        badgeTextView.setTextColor(colors.tagColorLevel4)
        badgeTextView.background = android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = dp2px(8f, resources.displayMetrics)
            setColor(androidx.core.graphics.ColorUtils.setAlphaComponent(colors.tagColorLevel4, 0x2E))
        }
        applyAccessory(colors)
    }

    private fun applyAccessory(colors: ColorTokens) {
        val hasCustomAccessory = customAccessoryResId != null
        val drawableResId = customAccessoryResId ?: if (showArrow) R.drawable.uikit_ic_arrow_right else null
        if (drawableResId == null) {
            accessoryImageView.visibility = GONE
            return
        }
        accessoryImageView.visibility = VISIBLE
        accessoryImageView.setImageResource(drawableResId)
        accessoryImageView.scaleX = 1f
        accessoryImageView.setColorFilter(
            when {
                hasCustomAccessory -> colors.textColorPrimary
                danger -> androidx.core.graphics.ColorUtils.setAlphaComponent(colors.textColorError, 0x99)
                else -> colors.textColorTertiary
            }
        )
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        viewScope?.launch {
            ThemeStore.shared(context).themeState.collectLatest {
                applyThemeColors(it.currentTheme.tokens.color)
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        viewScope?.cancel()
        viewScope = null
    }

    private fun getColors(): ColorTokens {
        return ThemeStore.shared(context).themeState.value.currentTheme.tokens.color
    }
}
