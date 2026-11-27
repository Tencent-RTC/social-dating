package io.trtc.tuikit.atomicx.albumpicker.view.likewhatsapp

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.lifecycle.findViewTreeLifecycleOwner
import io.trtc.tuikit.albumpickercore.api.AlbumListView
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreLanguage
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.atomicx.albumpicker.AlbumPickerConfig
import io.trtc.tuikit.atomicx.albumpicker.AlbumPickerListener
import io.trtc.tuikit.atomicx.albumpicker.R
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerUtil
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerWindowHelper
import io.trtc.tuikit.atomicx.albumpicker.view.common.AlbumPickerMainViewCommon
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreTheme

internal class WhatsAppAlbumPickerMainView(
    private val context: Context,
    private val store: AlbumPickerStore,
    private val previewView: WhatsAppAlbumPickerPreviewView,
    config: AlbumPickerConfig,
    listener: AlbumPickerListener?,
) : LinearLayout(context) {
    companion object {
        private const val ALBUM_LIST_SIZE_RATIO = 0.6
        private const val HD_BUTTON_BORDER_DP = 2
        private const val HD_BUTTON_FONT_SIZE = 12f
    }

    private val activity = context as? Activity
    private val theme = AlbumPickerCoreTheme.getInstance(context)
    private val common: AlbumPickerMainViewCommon
    private lateinit var bottomBar: WhatsAppBottomBarView
    private lateinit var hdButton: TextView
    private var isAddingMore = false
    private var activeDialog: AlertDialog? = null

    private val backPressedCallback =
        object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (!handleBackPressed()) {
                    listener?.onCancel()
                }
            }
        }

    init {
        orientation = VERTICAL
        layoutParams =
            FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)

        if (AlbumPickerCoreTheme.getInstance(context).confirmButtonIcon == null) {
            AlbumPickerCoreTheme.getInstance(context).confirmButtonIcon =
                ContextCompat.getDrawable(context, R.drawable.album_picker_ic_send)
        }

        common = AlbumPickerMainViewCommon(context, store, this, config, listener)
    }

    fun setup() {
        bottomBar =
            WhatsAppBottomBarView(context, store, listener = bottomBarListener).apply {
                visibility = View.GONE
            }

        previewView.listener = previewListener
        common.listener = commonListener
        common.setup(
            bottomBarView = bottomBar,
            tapMediaToSelect = true,
            albumListViewFactory = ::createAlbumListView,
        )

        setupHdButton()
    }

    private fun setupHdButton() {
        val headerLayout = getChildAt(0) as? FrameLayout ?: return
        val hPad = context.resources.getDimensionPixelSize(R.dimen.spacing_4)

        hdButton = TextView(context).apply {
            text = "HD"
            textSize = HD_BUTTON_FONT_SIZE
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(theme.textColor)
            gravity = Gravity.CENTER
            setPadding(hPad, hPad / 2, hPad, hPad / 2)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
            }
            setOnClickListener {
                val toggled = store.toggleOriginalSelection()
                updateHdButtonState()
                if (!toggled) {
                    showOriginalOversizedBlockedAlert()
                }
            }
        }
        headerLayout.addView(hdButton)
        updateHdButtonState()
    }

    private fun updateHdButtonState() {
        val cornerRadius = AlbumPickerUtil.dpToPx(context, theme.smallRadius).toFloat()
        val borderWidth = AlbumPickerUtil.dpToPx(context, HD_BUTTON_BORDER_DP)

        if (store.state.isOriginalSelected.value) {
            hdButton.setTextColor(Color.WHITE)
            hdButton.background = GradientDrawable().apply {
                setColor(theme.currentPrimaryColor)
                this.cornerRadius = cornerRadius
            }
        } else {
            hdButton.setTextColor(theme.textColor)
            hdButton.background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(borderWidth, theme.textColorSecondary)
                this.cornerRadius = cornerRadius
            }
        }
    }

    private val bottomBarListener =
        object : WhatsAppBottomBarView.Listener {
            override fun onClickSend(textMessage: String?) {
                common.deliverResult(textMessage)
            }

            override fun onPreviewClick() {
                val selected = store.state.selectedMedias.value.map { it.media }
                if (selected.isEmpty()) return
                store.updateCurrentPreviewMedia(selected.first())
                store.updatePreviewMedias(selected)
                bottomBar.hideSelectedThumbnails()
                previewView.setMessageText(bottomBar.getMessageText())
                previewView.show()
            }
        }

    private val previewListener =
        object : WhatsAppAlbumPickerPreviewView.Listener {
            override fun onClickSend(textMessage: String?) {
                common.deliverResult(textMessage)
            }

            override fun onAddMore() {
                isAddingMore = true
                previewView.hide()
                bottomBar.showSelectedThumbnails(
                    store.state.selectedMedias.value.map { it.media.uri },
                )
            }

            override fun onDismiss() {
                bottomBar.setMessageText(previewView.getMessageText())
                if (isAddingMore) {
                    isAddingMore = false
                    return
                }
                common.removeCapturedMedias()
            }
        }

    private val commonListener =
        object : AlbumPickerMainViewCommon.Listener {
            override fun onShowPreview(isPreviewFromSelection: Boolean) {
                bottomBar.hideSelectedThumbnails()
                previewView.setMessageText(bottomBar.getMessageText())
                previewView.show()
            }
        }

    private fun createAlbumListView(topOffset: Int, viewWidth: Int, viewHeight: Int): AlbumListView {
        val width = (viewWidth * ALBUM_LIST_SIZE_RATIO).toInt()
        val height = (viewHeight * ALBUM_LIST_SIZE_RATIO).toInt()
        val left = (viewWidth - width) / 2
        val rect = Rect(left, topOffset, left + width, topOffset + height)
        val pickerView = parent as? FrameLayout
        return AlbumListView(context, store, rect, pickerView)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        common.onAttachedToWindow()
        val containerView = parent as? View ?: return
        AlbumPickerWindowHelper.applySoftInputMode(activity, containerView, this, previewView) {
            bottomBar.collapse()
            previewView.collapseBottomBar()
        }
        val lifecycleOwner = findViewTreeLifecycleOwner() ?: return
        (context as? ComponentActivity)?.onBackPressedDispatcher
            ?.addCallback(lifecycleOwner, backPressedCallback)
    }

    override fun onDetachedFromWindow() {
        val containerView = parent as? View
        super.onDetachedFromWindow()
        common.onDetachedFromWindow()
        backPressedCallback.remove()
        activeDialog?.dismiss()
        activeDialog = null
        if (containerView != null) {
            AlbumPickerWindowHelper.restoreSoftInputMode(activity, containerView, this, previewView)
        }
    }

    private fun handleBackPressed(): Boolean {
        if (previewView.isEditViewVisible()) {
            if (!previewView.dispatchEditViewBack()) {
                previewView.dismissEditView()
            }
            return true
        }

        if (previewView.isVisible) {
            previewView.hide()
            return true
        }

        if (bottomBar.isInAddMoreMode()) {
            bottomBar.hideSelectedThumbnails()
            return true
        }

        if (bottomBar.collapse()) {
            return true
        }

        return common.handleBackPressed()
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
