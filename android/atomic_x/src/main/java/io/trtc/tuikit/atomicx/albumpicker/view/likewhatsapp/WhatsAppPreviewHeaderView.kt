package io.trtc.tuikit.atomicx.albumpicker.view.likewhatsapp

import android.content.Context
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreLanguage
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreTheme
import io.trtc.tuikit.albumpickercore.api.AlbumPickerMediaType
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.atomicx.albumpicker.R
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerUtil
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

internal class WhatsAppPreviewHeaderView(
    context: Context,
    private val store: AlbumPickerStore,
    private val listener: Listener,
) : FrameLayout(context) {
    interface Listener {
        fun onDismiss()

        fun onEditClick() {}
    }

    companion object {
        private const val HEADER_HEIGHT_DP = 44
        private const val BACK_ICON_SIZE_DP = 24
    }

    private val theme = AlbumPickerCoreTheme.getInstance(context)
    private val editButton: TextView
    private var mediaObserverJob: Job? = null

    init {
        val headerHeight = AlbumPickerUtil.dpToPx(context, HEADER_HEIGHT_DP)
        val horizontalPadding = resources.getDimensionPixelSize(R.dimen.spacing_16)
        val darkBackground = theme.darkBackground
        val darkTextColor = theme.darkTextColor

        layoutParams =
            LayoutParams(
                LayoutParams.MATCH_PARENT, headerHeight,
            ).apply {
                gravity = Gravity.TOP
            }
        setPadding(horizontalPadding, 0, horizontalPadding, 0)
        setBackgroundColor(darkBackground)

        val backIconSize = AlbumPickerUtil.dpToPx(context, BACK_ICON_SIZE_DP)
        val backButton =
            ImageView(context).apply {
                setImageResource(R.drawable.album_picker_ic_back)
                setColorFilter(darkTextColor)
                layoutParams =
                    LayoutParams(backIconSize, backIconSize).apply {
                        gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    }
                setOnClickListener { listener.onDismiss() }
            }
        addView(backButton)

        editButton =
            TextView(context).apply {
                text = AlbumPickerCoreLanguage.getString(context, R.string.album_picker_edit)
                textSize = theme.bigFontSize
                setTextColor(darkTextColor)
                gravity = Gravity.CENTER
                layoutParams =
                    LayoutParams(
                        LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT,
                    ).apply {
                        gravity = Gravity.END or Gravity.CENTER_VERTICAL
                    }
                setOnClickListener { listener.onEditClick() }
            }
        addView(editButton)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        val lifecycleOwner = findViewTreeLifecycleOwner() ?: return
        mediaObserverJob =
            lifecycleOwner.lifecycleScope.launch {
                store.state.currentPreviewMedia.collect { media ->
                    val editable = media != null && media.type != AlbumPickerMediaType.VIDEO
                    editButton.visibility = if (editable) VISIBLE else GONE
                }
            }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        mediaObserverJob?.cancel()
        mediaObserverJob = null
    }
}
