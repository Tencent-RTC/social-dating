package io.trtc.tuikit.atomicx.albumpicker.view.likewechat

import android.content.Context
import android.graphics.Bitmap
import android.widget.FrameLayout
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import io.trtc.tuikit.albumpickercore.api.AlbumMediaModel
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreTheme
import io.trtc.tuikit.albumpickercore.api.ImageEditView
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.albumpickercore.api.ImageEditListener
import io.trtc.tuikit.atomicx.albumpicker.view.common.AlbumPickerPreviewViewCommon
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class WeChatAlbumPickerPreviewView(
    context: Context,
    private val store: AlbumPickerStore,
) : FrameLayout(context) {
    interface Listener {
        fun onClickSend(textMessage: String? = null)

        fun onDismiss() {}
    }

    var listener: Listener? = null
    private var imageEditView: ImageEditView? = null

    private val bottomBarListener =
        object : WeChatBottomBarView.Listener {
            override fun onClickSend() {
                if (store.state.selectedMedias.value.any { !it.isPendingRemoval }) {
                    listener?.onClickSend()
                }
            }

            override fun onEditClick() {
                showImageEditView()
            }
        }

    private val headerView: WeChatPreviewHeaderView =
        WeChatPreviewHeaderView(
            context, store,
            WeChatPreviewHeaderView.OnDismissListener {
                hide()
            }
        )

    private val bottomBar =
        WeChatBottomBarView(context, store, isPreview = true).apply {
            this.listener =
                bottomBarListener
        }

    private val common =
        AlbumPickerPreviewViewCommon(
            container = this, store = store,
            headerView = headerView, bottomBarView = bottomBar
        )

    init {
        setBackgroundColor(AlbumPickerCoreTheme.getInstance(context).darkBackground)
    }

    fun show(isPreviewFromSelection: Boolean = false) {
        headerView.isPreviewFromSelection = isPreviewFromSelection
        headerView.startObserving()
        common.show()
    }

    fun hide() {
        headerView.stopObserving()
        common.hide()
        listener?.onDismiss()
    }

    fun isEditViewVisible(): Boolean = imageEditView != null

    fun dismissEditView() {
        dismissEditViewWithAnimation()
    }

    fun dispatchEditViewBack(): Boolean {
        return imageEditView?.onBackPressed() == true
    }

    private fun showImageEditView() {
        val currentMedia = store.state.currentPreviewMedia.value ?: return
        val editedBitmap = currentMedia.editedBitmap
        if (editedBitmap != null) {
            presentEditView(editedBitmap, currentMedia)
            return
        }
        val lifecycleOwner = context as? LifecycleOwner ?: return
        lifecycleOwner.lifecycleScope.launch {
            val bitmap = loadFullBitmap(currentMedia)
            if (bitmap != null) {
                presentEditView(bitmap, currentMedia)
            }
        }
    }

    private suspend fun loadFullBitmap(media: AlbumMediaModel): Bitmap? =
        withContext(Dispatchers.IO) {
            try {
                Glide.with(context)
                    .asBitmap()
                    .load(media.uri)
                    .diskCacheStrategy(DiskCacheStrategy.RESOURCE)
                    .submit()
                    .get()
            } catch (e: Exception) {
                null
            }
        }

    private fun presentEditView(bitmap: Bitmap, media: AlbumMediaModel) {
        imageEditView?.let {
            it.animate().cancel()
            removeView(it)
            imageEditView = null
        }
        val editListener = object : ImageEditListener {
            override fun onEditCompleted(editedBitmap: Bitmap) {
                store.updateEditedBitmap(media, editedBitmap)
                dismissEditView()
            }

            override fun onEditCancelled() {
                dismissEditView()
            }
        }
        val editView = ImageEditView(context, bitmap, editListener)
        editView.layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        editView.alpha = 0f
        addView(editView)
        editView.animate().alpha(1f).setDuration(200).start()
        imageEditView = editView
        common.onEnterEditMode()
    }

    private fun dismissEditViewWithAnimation() {
        val editView = imageEditView ?: return
        common.onExitEditMode()
        editView.animate().alpha(0f).setDuration(200).withEndAction {
            removeView(editView)
        }.start()
        imageEditView = null
    }
}
