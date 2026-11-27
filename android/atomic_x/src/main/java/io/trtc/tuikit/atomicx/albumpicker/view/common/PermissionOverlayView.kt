package io.trtc.tuikit.atomicx.albumpicker.view.common

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreLanguage
import io.trtc.tuikit.atomicx.albumpicker.R
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerUtil

internal enum class PermissionOverlayType(
    val titleRes: Int,
    val descriptionRes: Int,
) {
    MEDIA(
        R.string.album_picker_permission_media_title,
        R.string.album_picker_permission_media_description,
    ),
    STORAGE(
        R.string.album_picker_permission_storage_title,
        R.string.album_picker_permission_storage_description,
    ),
    CAMERA(
        R.string.album_picker_permission_camera_title,
        R.string.album_picker_permission_camera_description,
    ),
}

internal class PermissionOverlayView(
    context: Context,
    private val type: PermissionOverlayType,
) : FrameLayout(context) {

    private val title = AlbumPickerCoreLanguage.getString(context, type.titleRes)
    private val description = AlbumPickerCoreLanguage.getString(context, type.descriptionRes)

    companion object {
        private const val OVERLAY_ALPHA = 0.7f
        private const val CARD_WIDTH_DP = 240
        private const val CARD_PADDING_HORIZONTAL_DP = 16
        private const val CARD_PADDING_VERTICAL_DP = 10
        private const val CARD_TOP_MARGIN_DP = 8
        private const val TITLE_FONT_SIZE_SP = 18f
        private const val DESCRIPTION_FONT_SIZE_SP = 15f
        private const val TITLE_DESC_SPACING_DP = 4
    }

    init {
        setupView()
    }

    private fun setupView() {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        setBackgroundColor(Color.argb((255 * OVERLAY_ALPHA).toInt(), 0, 0, 0))
        isClickable = true
        isFocusable = true

        val card = createCard()
        val cardWidth = AlbumPickerUtil.dpToPx(context, CARD_WIDTH_DP)
        val cardParams = LayoutParams(cardWidth, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP
            topMargin = AlbumPickerUtil.dpToPx(context, CARD_TOP_MARGIN_DP)
        }
        addView(card, cardParams)
    }

    private fun createCard(): LinearLayout {
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            val hPad = AlbumPickerUtil.dpToPx(context, CARD_PADDING_HORIZONTAL_DP)
            val vPad = AlbumPickerUtil.dpToPx(context, CARD_PADDING_VERTICAL_DP)
            setPadding(hPad, vPad, hPad, vPad)
        }

        val titleView = TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, TITLE_FONT_SIZE_SP)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        card.addView(titleView)

        val descView = TextView(context).apply {
            text = description
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, DESCRIPTION_FONT_SIZE_SP)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = AlbumPickerUtil.dpToPx(context, TITLE_DESC_SPACING_DP)
            }
        }
        card.addView(descView)

        return card
    }

    fun show() {
        visibility = View.VISIBLE
    }

    fun dismiss() {
        visibility = View.GONE
    }
}
