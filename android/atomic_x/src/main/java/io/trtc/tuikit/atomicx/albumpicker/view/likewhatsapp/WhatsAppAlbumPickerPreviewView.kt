package io.trtc.tuikit.atomicx.albumpicker.view.likewhatsapp

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.widget.FrameLayout
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import io.trtc.tuikit.albumpickercore.api.AlbumMediaModel
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.albumpickercore.api.ImageEditListener
import io.trtc.tuikit.albumpickercore.api.ImageEditView
import io.trtc.tuikit.atomicx.albumpicker.view.common.AlbumPickerPreviewViewCommon
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class WhatsAppAlbumPickerPreviewView(
    context: Context,
    private val store: AlbumPickerStore,
) : FrameLayout(context) {
    interface Listener {
        fun onClickSend(textMessage: String? = null)

        fun onAddMore() {}

        fun onDismiss() {}
    }

    var listener: Listener? = null
    private var previewMediasObserverJob: Job? = null
    private var imageEditView: ImageEditView? = null

    private val bottomBarListener =
        object : WhatsAppBottomBarView.Listener {
            override fun onClickSend(textMessage: String?) {
                if (store.state.selectedMedias.value.any { !it.isPendingRemoval }) {
                    listener?.onClickSend(textMessage)
                }
            }

            override fun onAddMore() {
                listener?.onAddMore()
            }
        }

    private val headerViewListener =
        object : WhatsAppPreviewHeaderView.Listener {
            override fun onDismiss() {
                hide()
            }

            override fun onEditClick() {
                showImageEditView()
            }
        }

    private val headerView: WhatsAppPreviewHeaderView =
        WhatsAppPreviewHeaderView(context, store, headerViewListener)
    private val bottomBar =
        WhatsAppBottomBarView(context, store, isPreview = true, listener = bottomBarListener)
    private val common =
        AlbumPickerPreviewViewCommon(
            container = this,
            store = store,
            showDeleteButton = true,
            headerView = headerView,
            bottomBarView = bottomBar,
        )

    init {
        setBackgroundColor(Color.BLACK)
    }

    fun show() {
        common.show()
        startObservingPreviewMedias()
    }

    fun hide() {
        stopObservingPreviewMedias()
        bottomBar.collapse()
        common.hide()
        listener?.onDismiss()
    }

    fun collapseBottomBar() {
        bottomBar.collapse()
    }

    fun getMessageText(): String = bottomBar.getMessageText()

    fun setMessageText(text: String) {
        bottomBar.setMessageText(text)
    }

    private fun startObservingPreviewMedias() {
        stopObservingPreviewMedias()
        val lifecycleOwner = findViewTreeLifecycleOwner() ?: return
        previewMediasObserverJob =
            lifecycleOwner.lifecycleScope.launch {
                store.state.previewMedias.collect { medias ->
                    if (medias.isEmpty() && visibility == VISIBLE) {
                        hide()
                    }
                }
            }
    }

    private fun stopObservingPreviewMedias() {
        previewMediasObserverJob?.cancel()
        previewMediasObserverJob = null
    }

    fun isEditViewVisible(): Boolean = imageEditView != null

    fun dispatchEditViewBack(): Boolean = imageEditView?.onBackPressed() == true

    fun dismissEditView() {
        val editView = imageEditView ?: return
        common.onExitEditMode()
        editView.animate().alpha(0f).setDuration(EDIT_ANIM_DURATION_MS).withEndAction {
            removeView(editView)
        }.start()
        imageEditView = null
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
        val editListener =
            object : ImageEditListener {
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
        editView.animate().alpha(1f).setDuration(EDIT_ANIM_DURATION_MS).start()
        imageEditView = editView
        common.onEnterEditMode()
    }

    companion object {
        private const val EDIT_ANIM_DURATION_MS = 200L
    }
}
