package io.trtc.tuikit.atomicx.albumpicker.view.likewechat

import android.annotation.SuppressLint
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import androidx.core.graphics.ColorUtils
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.view.doOnLayout
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.trtc.tuikit.albumpickercore.api.AlbumMediaModel
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreLanguage
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreTheme
import io.trtc.tuikit.albumpickercore.api.AlbumPickerMediaType
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.atomicx.albumpicker.R
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerUtil
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

internal class WeChatBottomBarView(
    context: Context,
    private val store: AlbumPickerStore,
    private val isPreview: Boolean = false,
) : FrameLayout(context) {
    interface Listener {
        fun onClickSend()

        fun onPreviewClick() {}

        fun onEditClick() {}
    }

    companion object {
        private const val BAR_HEIGHT_DP = 54
        private const val INDICATOR_SIZE_DP = 20
        private const val INDICATOR_BORDER_WIDTH_DP = 1.5f
        private const val CHECKMARK_ICON_SIZE_DP = 14
    }

    var listener: Listener? = null

    private val theme = AlbumPickerCoreTheme.getInstance(context)

    private val bgColor =
        if (isPreview)
            theme.darkBackground else theme.backgroundColor

    private val bgColorSecondary =
        if (isPreview)
            theme.darkBackgroundSecondary else theme.backgroundColorSecondary

    private val txtColor =
        if (isPreview)
            theme.darkTextColor else theme.textColor

    private val txtColorSecondary =
        if (isPreview)
            theme.darkTextColorSecondary else theme.textColorSecondary

    private lateinit var sendText: TextView
    private var previewText: TextView? = null
    private var editText: TextView? = null
    private lateinit var originalContainer: LinearLayout
    private lateinit var originalIndicator: FrameLayout
    private lateinit var originalCheckmark: ImageView
    private lateinit var originalText: TextView
    private lateinit var originalSizeText: TextView
    private var selectedCount: Int = 0
    private var totalSizeBytes: Long = 0
    private var observeJob: Job? = null
    private var originalObserveJob: Job? = null
    private var previewMediaObserveJob: Job? = null
    private var activeDialog: AlertDialog? = null

    init {
        setupViews()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startObserving()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopObserving()
        activeDialog?.dismiss()
        activeDialog = null
    }

    private fun startObserving() {
        stopObserving()
        val lifecycleOwner = context as? LifecycleOwner ?: return
        observeJob =
            lifecycleOwner.lifecycleScope.launch {
                store.state.selectedMedias.collectLatest { selectedMedias ->
                    val activeItems = if (isPreview) {
                        selectedMedias.filter { !it.isPendingRemoval }
                    } else {
                        selectedMedias
                    }
                    totalSizeBytes = activeItems.sumOf { it.media.size }
                    updateState(activeItems.size)
                }
            }
        originalObserveJob =
            lifecycleOwner.lifecycleScope.launch {
                store.state.isOriginalSelected.collectLatest {
                    updateOriginalState()
                }
            }
        if (isPreview) {
            previewMediaObserveJob =
                lifecycleOwner.lifecycleScope.launch {
                    store.state.currentPreviewMedia.collectLatest { media ->
                        updateEditButtonState(media)
                    }
                }
        }
    }

    private fun stopObserving() {
        observeJob?.cancel()
        observeJob = null
        originalObserveJob?.cancel()
        originalObserveJob = null
        previewMediaObserveJob?.cancel()
        previewMediaObserveJob = null
    }

    private fun setupViews() {
        val barHeight = AlbumPickerUtil.dpToPx(context, BAR_HEIGHT_DP)
        val horizontalPadding = resources.getDimensionPixelSize(R.dimen.spacing_16)

        layoutParams =
            if (isPreview) {
                LayoutParams(LayoutParams.MATCH_PARENT, barHeight).apply {
                    gravity = Gravity.BOTTOM
                }
            } else {
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, barHeight)
            }
        setBackgroundColor(bgColor)
        setPadding(horizontalPadding, 0, horizontalPadding, 0)
        clipChildren = false
        clipToPadding = false

        if (isPreview) {
            editText = createEditText()
            addView(editText)
        } else {
            previewText = createPreviewText()
            addView(previewText)
        }

        originalContainer = createOriginalButton()
        originalSizeText = createOriginalSizeText()

        val originalWrapper = FrameLayout(context).apply {
            clipChildren = false
            clipToPadding = false
            layoutParams = LayoutParams(
                LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
            }
            addView(originalContainer)
            addView(originalSizeText)
        }
        addView(originalWrapper)

        sendText = createSendText()
        addView(sendText)

        updateState(0)
    }

    private fun createEditText(): TextView {
        val editLayoutParams =
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            }
        return TextView(context).apply {
            text = AlbumPickerCoreLanguage.getString(context, R.string.album_picker_edit)
            textSize = theme.bigFontSize
            setTextColor(txtColor)
            gravity = Gravity.CENTER
            layoutParams = editLayoutParams
            setOnClickListener { listener?.onEditClick() }
        }
    }

    private fun createPreviewText(): TextView {
        val previewLayoutParams =
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            }
        return TextView(context).apply {
            text = AlbumPickerCoreLanguage.getString(context, R.string.album_picker_preview)
            textSize = theme.bigFontSize
            setTextColor(txtColorSecondary)
            gravity = Gravity.CENTER
            layoutParams = previewLayoutParams
            setOnClickListener {
                if (selectedCount > 0) listener?.onPreviewClick()
            }
        }
    }

    private fun createOriginalButton(): LinearLayout {
        val spacing = context.resources.getDimensionPixelSize(R.dimen.spacing_4)

        originalIndicator = createOriginalIndicator()
        originalText = createOriginalLabel(spacing)

        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LayoutParams(
                LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER }
            addView(originalIndicator)
            addView(originalText)
            setOnClickListener {
                val toggled = store.toggleOriginalSelection()
                if (!toggled) {
                    showOriginalOversizedBlockedAlert()
                }
            }
        }
    }

    private fun createOriginalIndicator(): FrameLayout {
        val indicatorSize = AlbumPickerUtil.dpToPx(context, INDICATOR_SIZE_DP)
        val checkmarkSize = AlbumPickerUtil.dpToPx(context, CHECKMARK_ICON_SIZE_DP)

        val indicator = FrameLayout(context).apply {
            isClickable = false
            isFocusable = false
            layoutParams = LinearLayout.LayoutParams(indicatorSize, indicatorSize).apply {
                gravity = Gravity.CENTER_VERTICAL
            }
        }

        val checkmark = ImageView(context).apply {
            setImageDrawable(AppCompatResources.getDrawable(context, R.drawable.album_picker_ic_done))
            visibility = GONE
            isClickable = false
            isFocusable = false
            layoutParams = LayoutParams(checkmarkSize, checkmarkSize).apply {
                gravity = Gravity.CENTER
            }
        }
        indicator.addView(checkmark)
        originalCheckmark = checkmark

        return indicator
    }

    private fun createOriginalLabel(marginStart: Int): TextView {
        return TextView(context).apply {
            text = AlbumPickerCoreLanguage.getString(context, R.string.album_picker_original)
            textSize = theme.bigFontSize
            setTextColor(txtColor)
            gravity = Gravity.CENTER
            isClickable = false
            isFocusable = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_VERTICAL
                this.marginStart = marginStart
            }
        }
    }

    private fun createOriginalSizeText(): TextView {
        return TextView(context).apply {
            textSize = theme.smallFontSize
            setTextColor(txtColorSecondary)
            gravity = Gravity.CENTER
            visibility = GONE
            isClickable = false
            isFocusable = false
            layoutParams = LayoutParams(
                LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM
            }
        }
    }

    private fun updateOriginalSizeText() {
        if (store.state.isOriginalSelected.value && totalSizeBytes > 0) {
            val sizeStr = formatFileSize(totalSizeBytes)
            originalSizeText.text = String.format(
                AlbumPickerCoreLanguage.getString(context, R.string.album_picker_total_size),
                sizeStr
            )
            originalSizeText.visibility = VISIBLE
            originalContainer.doOnLayout {
                val gap = AlbumPickerUtil.dpToPx(context, 1)
                originalSizeText.translationY = it.height.toFloat() / 2 + gap
            }
        } else {
            originalSizeText.visibility = GONE
        }
    }

    private fun formatFileSize(bytes: Long): String {
        val gb = 1024L * 1024L * 1024L
        val mb = 1024L * 1024L
        val kb = 1024L
        return when {
            bytes >= gb -> String.format("%.1fGB", bytes.toDouble() / gb)
            bytes >= mb -> "${bytes / mb}MB"
            else -> "${maxOf(bytes / kb, 1)}KB"
        }
    }

    private fun updateOriginalState() {
         val indicatorBorderPx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, INDICATOR_BORDER_WIDTH_DP, context.resources.displayMetrics,
        ).toInt()

        val indicatorSizePx = AlbumPickerUtil.dpToPx(context, INDICATOR_SIZE_DP)

        if (store.state.isOriginalSelected.value) {
            originalCheckmark.visibility = VISIBLE
            originalIndicator.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(theme.currentPrimaryColor)
                setSize(indicatorSizePx, indicatorSizePx)
            }
        } else {
            originalCheckmark.visibility = GONE
            originalIndicator.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke(indicatorBorderPx, txtColor)
                setSize(indicatorSizePx, indicatorSizePx)
            }
        }
        originalText.setTextColor(txtColor)
        updateOriginalSizeText()
    }

    private fun updateEditButtonState(media: AlbumMediaModel?) {
        val isVideo = media?.type == AlbumPickerMediaType.VIDEO
        editText?.alpha = if (isVideo) 0.4f else 1.0f
        editText?.isEnabled = !isVideo
    }

    private fun createSendText(): TextView {
        val sendHPadding = resources.getDimensionPixelSize(R.dimen.spacing_10)
        val sendVPadding = resources.getDimensionPixelSize(R.dimen.spacing_4)
        val cornerRadius = AlbumPickerUtil.dpToPx(context, theme.smallRadius).toFloat()
        val sendLayoutParams =
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
            }
        val sendBackground =
            GradientDrawable().apply {
                setColor(bgColorSecondary)
                this.cornerRadius = cornerRadius
            }
        return TextView(context).apply {
            text = AlbumPickerCoreLanguage.getString(context, R.string.album_picker_send)
            textSize = theme.bigFontSize
            setTextColor(txtColorSecondary)
            gravity = Gravity.CENTER
            setPadding(sendHPadding, sendVPadding, sendHPadding, sendVPadding)
            layoutParams = sendLayoutParams
            background = sendBackground
            setOnClickListener {
                if (isPreview || selectedCount > 0) listener?.onClickSend()
            }
        }
    }

    @SuppressLint("SetTextI18n")
    private fun updateState(count: Int) {
        selectedCount = count
        val cornerRadius = AlbumPickerUtil.dpToPx(context, theme.smallRadius).toFloat()

        if (count > 0) {
            previewText?.text =
                "${AlbumPickerCoreLanguage.getString(context, R.string.album_picker_preview)}($count)"
            previewText?.setTextColor(txtColor)

            sendText.text =
                "${AlbumPickerCoreLanguage.getString(context, R.string.album_picker_send)}($count)"
            sendText.setTextColor(Color.WHITE)
            sendText.background =
                GradientDrawable().apply {
                    setColor(theme.currentPrimaryColor)
                    this.cornerRadius = cornerRadius
                }
        } else {
            previewText?.text =
                AlbumPickerCoreLanguage.getString(context, R.string.album_picker_preview)
            previewText?.setTextColor(txtColorSecondary)

            sendText.text = AlbumPickerCoreLanguage.getString(context, R.string.album_picker_send)
            sendText.setTextColor(txtColorSecondary)
            sendText.background =
                GradientDrawable().apply {
                    setColor(bgColorSecondary)
                    this.cornerRadius = cornerRadius
                }
        }

        updateOriginalState()
    }

    private fun showOriginalOversizedBlockedAlert() {
        val size = store.config.maxOutputFileSizeInMB
        val message = AlbumPickerCoreLanguage.getString(
            context, R.string.album_picker_original_oversized_blocked, size
        )
        val buttonText = AlbumPickerCoreLanguage.getString(
            context, R.string.album_picker_i_know
        )
        activeDialog?.dismiss()
        activeDialog = AlertDialog.Builder(context, android.R.style.Theme_Material_Light_Dialog_Alert)
            .setMessage(message)
            .setPositiveButton(buttonText, null)
            .show()
    }
}
