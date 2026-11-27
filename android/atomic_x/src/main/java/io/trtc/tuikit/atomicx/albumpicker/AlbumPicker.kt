package io.trtc.tuikit.atomicx.albumpicker

import android.content.Context
import android.graphics.drawable.Drawable
import android.net.Uri
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.ColorInt
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreLanguage
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreTheme
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStoreConfig
import io.trtc.tuikit.albumpickercore.api.CompressQuality
import io.trtc.tuikit.atomicx.albumpicker.view.likewechat.WeChatAlbumPickerMainView
import io.trtc.tuikit.atomicx.albumpicker.view.likewechat.WeChatAlbumPickerPreviewView
import io.trtc.tuikit.atomicx.albumpicker.view.likewhatsapp.WhatsAppAlbumPickerMainView
import io.trtc.tuikit.atomicx.albumpicker.view.likewhatsapp.WhatsAppAlbumPickerPreviewView

enum class AlbumMediaType { IMAGE, VIDEO }

enum class AlbumPickerMediaFilter {
    ALL,
    IMAGE_ONLY,
    VIDEO_ONLY,
}

enum class AlbumPickerStyle { LIKE_WECHAT, LIKE_WHATSAPP }

typealias AlbumPickerLanguage = AlbumPickerCoreLanguage.Language

typealias AlbumPickerCompressQuality = CompressQuality

data class AlbumMedia(
    val id: ULong,
    var uri: Uri?,
    var mediaPath: String? = null,
    var mediaType: AlbumMediaType = AlbumMediaType.IMAGE,
    var videoThumbnailPath: String? = null,
    var duration: Long = 0,
)

data class AlbumPickerConfig(
    var mediaFilter: AlbumPickerMediaFilter = AlbumPickerMediaFilter.ALL,
    var maxSelectionCount: Int? = null,
    var itemsPerRow: Int? = null,
    var showsCameraItem: Boolean = false,
    var style: AlbumPickerStyle = AlbumPickerStyle.LIKE_WECHAT,
    var language: AlbumPickerLanguage? = null,
    var compressQuality: AlbumPickerCompressQuality = AlbumPickerCompressQuality.STANDARD,
    var maxVideoDurationInSeconds: Int = 600,
    var maxOutputFileSizeInMB: Int = 100,
)

data class AlbumPickerTheme(
    @ColorInt var currentPrimaryColor: Int? = null,
    @ColorInt var backgroundColor: Int? = null,
    @ColorInt var backgroundColorSecondary: Int? = null,
    @ColorInt var textColor: Int? = null,
    @ColorInt var textColorSecondary: Int? = null,
    var smallRadius: Int? = null,
    var normalRadius: Int? = null,
    var bigRadius: Int? = null,
    var bigFontSize: Float? = null,
    var normalFontSize: Float? = null,
    var smallFontSize: Float? = null,
    var confirmButtonIcon: Drawable? = null,
)

interface AlbumPickerListener {
    fun onPickConfirm(pickedAlbumMedias: List<AlbumMedia>, textMessage: String?)

    fun onMediaProcessing(albumMedia: AlbumMedia, progress: Float, error: Boolean)

    fun onMediaProcessed()

    fun onCancel()
}

class AlbumPickerView
    @JvmOverloads
    constructor(
        context: Context,
        attrs: AttributeSet? = null,
        defStyleAttr: Int = 0,
    ) : FrameLayout(context) {
        private var isInitialized = false

        fun initialize(config: AlbumPickerConfig,
                       theme: AlbumPickerTheme, listener: AlbumPickerListener?) {
            if (isInitialized) {
                return
            }
            isInitialized = true

            Log.i("AlbumPicker", "AlbumPicker version: ${BuildConfig.VERSION_NAME}")

            AlbumPickerCoreLanguage.shared.current = config.language ?: AlbumPickerLanguage.SYSTEM

            val coreTheme = AlbumPickerCoreTheme.getInstance(context)
            coreTheme.initialize(
                context, theme.currentPrimaryColor, theme.backgroundColor,
                theme.backgroundColorSecondary, theme.textColor, theme.textColorSecondary,
                theme.smallRadius, theme.normalRadius, theme.bigRadius,
                theme.bigFontSize, theme.normalFontSize, theme.smallFontSize,
                theme.confirmButtonIcon,
            )

            val store = AlbumPickerStore(context)
            store.config = AlbumPickerStoreConfig(
                maxSelectionCount = config.maxSelectionCount ?: 9,
                maxVideoDurationInSeconds = config.maxVideoDurationInSeconds,
                maxOutputFileSizeInMB = config.maxOutputFileSizeInMB,
                compressQuality = config.compressQuality,
            )
            val previewView: View
            val mainView: View

            when (config.style) {
                AlbumPickerStyle.LIKE_WHATSAPP -> {
                    previewView = WhatsAppAlbumPickerPreviewView(context, store)
                    mainView =
                        WhatsAppAlbumPickerMainView(context, store, previewView, config, listener).also {
                            it.setup()
                        }
                }

                AlbumPickerStyle.LIKE_WECHAT -> {
                    previewView = WeChatAlbumPickerPreviewView(context, store)
                    mainView =
                        WeChatAlbumPickerMainView(context, store, previewView, config, listener).also {
                            it.setup()
                        }
                }
            }

            setBackgroundColor(AlbumPickerCoreTheme.getInstance(context).backgroundColor)
            addView(mainView)
            previewView.layoutParams =
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            previewView.visibility = GONE
            addView(previewView)
        }
    }
