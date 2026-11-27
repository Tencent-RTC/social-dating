package io.trtc.tuikit.atomicx.albumpicker.view.common

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.graphics.Typeface
import android.net.Uri
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.trtc.tuikit.albumpickercore.api.AlbumListView
import io.trtc.tuikit.albumpickercore.api.AlbumMediaModel
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreLanguage
import io.trtc.tuikit.albumpickercore.api.AlbumPickerCoreTheme
import io.trtc.tuikit.albumpickercore.api.AlbumPickerMediaGridConfig
import io.trtc.tuikit.albumpickercore.api.AlbumPickerMediaGridView
import io.trtc.tuikit.albumpickercore.api.AlbumPickerMediaProcessListener
import io.trtc.tuikit.albumpickercore.api.AlbumPickerMediaType
import io.trtc.tuikit.albumpickercore.api.AlbumPickerStore
import io.trtc.tuikit.albumpickercore.api.MediaSelectionResult
import io.trtc.tuikit.albumpickercore.api.SelectedMediaItem
import io.trtc.tuikit.atomicx.albumpicker.AlbumMedia
import io.trtc.tuikit.atomicx.albumpicker.AlbumMediaType
import io.trtc.tuikit.atomicx.albumpicker.AlbumPickerConfig
import io.trtc.tuikit.atomicx.albumpicker.AlbumPickerListener
import io.trtc.tuikit.atomicx.albumpicker.AlbumPickerMediaFilter
import io.trtc.tuikit.atomicx.albumpicker.AlbumPickerStyle
import io.trtc.tuikit.atomicx.albumpicker.R
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerPermissionRequester
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerUtil
import io.trtc.tuikit.atomicx.albumpicker.util.AlbumPickerWindowHelper
import io.trtc.tuikit.atomicx.albumpicker.util.PermissionState
import io.trtc.tuikit.atomicx.albumpicker.util.PermissionType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

internal class AlbumPickerMainViewCommon(
    private val context: Context,
    private val store: AlbumPickerStore,
    private val contentView: LinearLayout,
    private val config: AlbumPickerConfig,
    private val albumPickerListener: AlbumPickerListener?,
) {
    interface Listener {
        fun onShowPreview(isPreviewFromSelection: Boolean)
    }

    companion object {
        private const val BANNER_ICON_SIZE_DP = 20
        private const val DEFAULT_MAX_SELECTION_COUNT = 9
        private const val MIN_ITEMS_PER_ROW = 2
        private const val MAX_ITEMS_PER_ROW = 5

        fun showSelectionFailedAlert(
            context: Context,
            result: MediaSelectionResult,
            store: AlbumPickerStore,
        ) {
            val message: String = when (result) {
                MediaSelectionResult.SUCCESS -> return
                MediaSelectionResult.VIDEO_DURATION_EXCEEDED -> {
                    val minutes = store.config.maxVideoDurationInSeconds / 60
                    context.getString(R.string.album_picker_video_duration_exceeded, minutes)
                }
                MediaSelectionResult.FILE_SIZE_EXCEEDED -> {
                    val size = store.config.maxOutputFileSizeInMB
                    context.getString(R.string.album_picker_file_size_exceeded, size)
                }
                MediaSelectionResult.MAX_SELECTION_COUNT_EXCEEDED -> {
                    val count = store.config.maxSelectionCount
                    context.getString(R.string.album_picker_max_selection_exceeded, count)
                }
            }
            AlertDialog.Builder(context, android.R.style.Theme_Material_Light_Dialog_Alert)
                .setMessage(message)
                .setPositiveButton(R.string.album_picker_i_know, null)
                .show()
        }
    }

    var listener: Listener? = null

    private val isWithVideo = config.mediaFilter != AlbumPickerMediaFilter.IMAGE_ONLY
    private val isWithImage = config.mediaFilter != AlbumPickerMediaFilter.VIDEO_ONLY
    private val theme = AlbumPickerCoreTheme.getInstance(context)
    private var tapMediaToSelect: Boolean = false
    private val activity = context as? Activity

    private fun defaultItemsPerRow(): Int = when (config.style) {
        AlbumPickerStyle.LIKE_WHATSAPP -> 3
        AlbumPickerStyle.LIKE_WECHAT -> 3
    }

    private lateinit var headerLayout: FrameLayout
    private lateinit var selectMoreBanner: LinearLayout
    private lateinit var settingsBanner: LinearLayout
    private lateinit var mediaGridView: AlbumPickerMediaGridView

    private var bottomBarView: View? = null
    private var albumListViewFactory:
        ((topOffset: Int, viewWidth: Int, viewHeight: Int) -> AlbumListView)? = null
    private var albumListView: AlbumListView? = null

    private var camera: AlbumPickerCamera? = null
    private var permissionRequester: AlbumPickerPermissionRequester? = null
    private val capturedMediaIds: MutableSet<String> = mutableSetOf()
    private var selectionObserverJob: Job? = null
    private var hasPendingPermissionRequest = false
    private var lifecycleObserver: LifecycleEventObserver? = null
    private var permissionOverlay: PermissionOverlayView? = null

    fun setup(
        bottomBarView: View? = null,
        albumListViewFactory: ((topOffset: Int, viewWidth: Int, viewHeight: Int) -> AlbumListView)? =
            null,
        tapMediaToSelect: Boolean = false,
    ) {
        this.tapMediaToSelect = tapMediaToSelect
        this.bottomBarView = bottomBarView
        this.albumListViewFactory = albumListViewFactory
        registerActivityResultLaunchers()
        setupViews()
    }

    fun onAttachedToWindow() {
        loadAlbumsWithPermissionCheck()
        contentView.post {
            val pickerView = contentView.parent as? View ?: contentView
            AlbumPickerWindowHelper.setupEdgeToEdge(activity, pickerView) {
                AlbumPickerWindowHelper.applySystemBarColor(activity, theme.backgroundColor)
            }
            registerLifecycleObserver()
        }
        startObservingSelectionLimit()
    }

    fun onDetachedFromWindow() {
        camera?.unregister()
        permissionRequester?.unregister()
        selectionObserverJob?.cancel()
        selectionObserverJob = null
        unregisterLifecycleObserver()
        AlbumPickerWindowHelper.restoreSystemBarColor(activity, contentView.parent as? View)
    }

    fun handleBackPressed(): Boolean = albumListView?.tryDismissPopupPanel() == true

    fun deliverResult(textMessage: String? = null) {
        clearCapturedMediaIds()
        val selectedMedias = store.state.selectedMedias.value.filter { !it.isPendingRemoval }
        store.updateSelectedMedias(selectedMedias)
        val albumMedias = selectedMedias.map { convertToAlbumMedia(it) }

        val mediaModelIdToAlbumMedia = mutableMapOf<String, AlbumMedia>()
        for (i in selectedMedias.indices) {
            mediaModelIdToAlbumMedia[selectedMedias[i].media.id] = albumMedias[i]
        }

        albumPickerListener?.onPickConfirm(albumMedias, textMessage)

        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            store.processSelectedMedias(
                createMediaProcessListener(mediaModelIdToAlbumMedia))
        }
    }

    fun removeCapturedMedias() {
        if (capturedMediaIds.isEmpty()) return
        val currentSelected = store.state.selectedMedias.value
        store.updateSelectedMedias(currentSelected.filter { it.media.id !in capturedMediaIds })
        capturedMediaIds.clear()
    }

    private fun convertToAlbumMedia(item: SelectedMediaItem): AlbumMedia {
        val isVideo = item.media.type == AlbumPickerMediaType.VIDEO
        return AlbumMedia(
            id = item.media.id.toULongOrNull() ?: 0u,
            uri = item.media.uri,
            mediaPath = item.media.mediaPath,
            mediaType = if (isVideo) AlbumMediaType.VIDEO else AlbumMediaType.IMAGE,
            duration = item.media.duration.toLong(),
        )
    }

    private fun createMediaProcessListener(mediaModelIdToAlbumMedia: Map<String, AlbumMedia>):
        AlbumPickerMediaProcessListener = object : AlbumPickerMediaProcessListener {
        override fun onMediaProcessing(media: AlbumMediaModel, progress: Float, error: Boolean) {
            val albumMedia = mediaModelIdToAlbumMedia[media.id] ?: return
            albumMedia.mediaPath = media.mediaPath
            albumMedia.videoThumbnailPath = media.videoThumbnailPath
            albumMedia.duration = media.duration.toLong()
            if (media.editedBitmap != null) {
                albumMedia.uri = media.uri
            }
            albumPickerListener?.onMediaProcessing(albumMedia, progress, error)
        }

        override fun onMediaProcessed() {
            albumPickerListener?.onMediaProcessed()
        }
    }

    private fun registerActivityResultLaunchers() {
        val registry = (context as? ComponentActivity)?.activityResultRegistry ?: return

        camera =
            AlbumPickerCamera(
                context, registry,
                isWithImage = isWithImage, isWithVideo = isWithVideo,
                onCaptureResult = ::onCameraCaptureResult,
                onShowPermissionOverlay = { showPermissionOverlay(PermissionOverlayType.CAMERA) },
                onDismissPermissionOverlay = ::dismissPermissionOverlay,
            )

        permissionRequester =
            AlbumPickerPermissionRequester(registry, context) {
                hasPendingPermissionRequest = false
                dismissPermissionOverlay()
                updateLimitedAccessBanner()
                store.loadAllAlbums(isWithVideo = isWithVideo, isWithImage = isWithImage)
            }
    }

    private fun onCameraCaptureResult(medias: List<AlbumMedia>) {
        val capturedMediaModels = medias.map { convertToAlbumMediaModel(it) }
        capturedMediaModels.forEach { capturedMediaIds.add(it.id) }
        val currentSelected = store.state.selectedMedias.value
        val newItems = capturedMediaModels.map {
            SelectedMediaItem(media = it, isPendingRemoval = false)
        }
        store.updateSelectedMedias(currentSelected + newItems)

        val selected = store.state.selectedMedias.value.map { it.media }
        if (selected.isEmpty()) return
        store.updateCurrentPreviewMedia(capturedMediaModels.first())
        store.updatePreviewMedias(selected)
        listener?.onShowPreview(isPreviewFromSelection = true)
    }

    private fun setupViews() {
        setupHeader()
        setupBanners()
        setupMediaGridView()

        contentView.addView(headerLayout)
        contentView.addView(selectMoreBanner)
        contentView.addView(mediaGridView)
        contentView.addView(settingsBanner)
        bottomBarView?.let { contentView.addView(it) }
    }

    private fun setupHeader() {
        val spacing = context.resources.getDimensionPixelSize(R.dimen.spacing_10)

        headerLayout =
            FrameLayout(context).apply {
                layoutParams =
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    )
                setPadding(
                    spacing, spacing,
                    spacing, spacing,
                )
            }

        val iconSize = context.resources.getDimensionPixelSize(R.dimen.spacing_24)
        val closeButton =
            ImageView(context).apply {
                setImageResource(R.drawable.album_picker_ic_close)
                setColorFilter(theme.textColor)
                layoutParams =
                    FrameLayout.LayoutParams(iconSize, iconSize)
                        .apply { gravity = Gravity.START or Gravity.CENTER_VERTICAL }
                setOnClickListener { albumPickerListener?.onCancel() }
            }
        headerLayout.addView(closeButton)
        headerLayout.post { setupAlbumListView() }
    }

    private fun setupAlbumListView() {
        val topOffset = headerLayout.bottom
        val viewWidth = contentView.width
        val viewHeight = contentView.height

        val albumListView =
            albumListViewFactory?.invoke(topOffset, viewWidth, viewHeight)
                ?: AlbumListView(context, store, Rect(0, topOffset, viewWidth, viewHeight))

        this.albumListView = albumListView
        headerLayout.addView(albumListView)
    }

    private fun setupBanners() {
        val iconTextSpacing = context.resources.getDimensionPixelSize(R.dimen.spacing_4)
        val iconIconSpacing = context.resources.getDimensionPixelSize(R.dimen.spacing_8)

        selectMoreBanner =
            createBannerItem(
                R.drawable.album_picker_ic_warning,
                R.string.album_picker_select_more_photos,
                iconTextSpacing,
                iconIconSpacing,
            ) {
                hasPendingPermissionRequest = true
                permissionRequester?.requestPermissions()
            }.apply { visibility = View.GONE }

        settingsBanner =
            createBannerItem(
                R.drawable.album_picker_ic_settings,
                R.string.album_picker_go_to_settings,
                iconTextSpacing,
                iconIconSpacing,
            ) {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", context.packageName, null)
                    },
                )
            }.apply { visibility = View.GONE }
    }

    private fun setupMediaGridView() {
        mediaGridView =
            AlbumPickerMediaGridView(
                context = context, store = store,
                config =
                    AlbumPickerMediaGridConfig(
                        itemsPerRow = (config.itemsPerRow ?: defaultItemsPerRow())
                            .coerceIn(MIN_ITEMS_PER_ROW, MAX_ITEMS_PER_ROW),
                        showsCameraItem = config.showsCameraItem,
                        tapToSelect = tapMediaToSelect,
                    ),
                listener = mediaGridListener,
            ).apply {
                layoutParams =
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
                clipToPadding = false
            }
    }

    private val mediaGridListener =
        object : AlbumPickerMediaGridView.Listener {
            override fun onCameraClick() {
                camera?.launch()
            }

            override fun onMediaClick(mediaModel: AlbumMediaModel) {
                val previewMedias = store.state.currentAlbum.value.mediaModels
                store.updateCurrentPreviewMedia(mediaModel)
                store.updatePreviewMedias(previewMedias)
                listener?.onShowPreview(isPreviewFromSelection = false)
            }

            override fun onSelectionFailed(result: MediaSelectionResult) {
                handleSelectionResult(result)
            }
        }

    private fun handleSelectionResult(result: MediaSelectionResult) {
        showSelectionFailedAlert(context, result, store)
    }

    private fun loadAlbumsWithPermissionCheck() {
        val permissionState = permissionRequester?.currentPermissionState() ?: return
        val notDetermined = permissionState == PermissionState.NOT_DETERMINED
        val denied = permissionState == PermissionState.DENIED
        val limited = permissionState == PermissionState.LIMITED
        val photoPickerAvail = ActivityResultContracts.PickVisualMedia.isPhotoPickerAvailable(context)

        if (notDetermined || denied || (!photoPickerAvail && limited)) {
            hasPendingPermissionRequest = true
            val overlayType = when (permissionRequester?.currentPermissionType()) {
                PermissionType.MEDIA -> PermissionOverlayType.MEDIA
                PermissionType.STORAGE -> PermissionOverlayType.STORAGE
                else -> PermissionOverlayType.MEDIA
            }
            showPermissionOverlay(overlayType)
            permissionRequester?.requestPermissions()
        }

        updateLimitedAccessBanner()
        store.loadAllAlbums(isWithVideo = isWithVideo, isWithImage = isWithImage)
    }

    private fun updateLimitedAccessBanner() {
        val permissionState = permissionRequester?.currentPermissionState() ?: return
        val limited = permissionState == PermissionState.LIMITED
        val denied = permissionState == PermissionState.DENIED
        val photoPickerAvail = ActivityResultContracts.PickVisualMedia.isPhotoPickerAvailable(context)

        if (!limited && !denied) {
            selectMoreBanner.visibility = View.GONE
            settingsBanner.visibility = View.GONE
            return
        }

        selectMoreBanner.visibility = if (limited && photoPickerAvail) View.VISIBLE else View.GONE
        settingsBanner.visibility = View.VISIBLE
        repositionSettingsBanner(limited && photoPickerAvail)
    }

    private fun repositionSettingsBanner(photoPickerAvail: Boolean) {
        contentView.removeView(settingsBanner)
        val insertIndex =
            if (photoPickerAvail) {
                findInsertIndexBeforeBottomBar()
            } else {
                contentView.indexOfChild(selectMoreBanner) + 1
            }
        contentView.addView(settingsBanner, insertIndex)
    }

    private fun findInsertIndexBeforeBottomBar(): Int {
        val bottomBar = bottomBarView ?: return contentView.childCount
        val index = contentView.indexOfChild(bottomBar)
        return if (index >= 0) index else contentView.childCount
    }

    private fun clearCapturedMediaIds() {
        capturedMediaIds.clear()
    }

    private fun registerLifecycleObserver() {
        val lifecycleOwner = contentView.findViewTreeLifecycleOwner() ?: return
        val observer = LifecycleEventObserver { _, event ->
            if (event != Lifecycle.Event.ON_RESUME) {
                return@LifecycleEventObserver
            }
            camera?.onResume()
            if (!hasPendingPermissionRequest && permissionOverlay == null) {
                return@LifecycleEventObserver
            }
            hasPendingPermissionRequest = false
            dismissPermissionOverlay()
            updateLimitedAccessBanner()
            store.loadAllAlbums(isWithVideo = isWithVideo, isWithImage = isWithImage)
        }
        lifecycleObserver = observer
        lifecycleOwner.lifecycle.addObserver(observer)
    }

    private fun unregisterLifecycleObserver() {
        val lifecycleOwner = contentView.findViewTreeLifecycleOwner()
        lifecycleObserver?.let { lifecycleOwner?.lifecycle?.removeObserver(it) }
        lifecycleObserver = null
    }

    private fun startObservingSelectionLimit() {
        val maxCount = config.maxSelectionCount ?: DEFAULT_MAX_SELECTION_COUNT
        val lifecycleOwner = contentView.findViewTreeLifecycleOwner() ?: return
        selectionObserverJob?.cancel()
        selectionObserverJob =
            lifecycleOwner.lifecycleScope.launch {
                store.state.selectedMedias.collect { selectedItems ->
                    if (selectedItems.size > maxCount) {
                        store.updateSelectedMedias(selectedItems.take(maxCount))
                    }
                }
            }
    }

    private fun convertToAlbumMediaModel(albumMedia: AlbumMedia): AlbumMediaModel =
        AlbumMediaModel(
            id = albumMedia.id.toString(),
            uri = albumMedia.uri ?: Uri.EMPTY,
            type =
                if (albumMedia.mediaType == AlbumMediaType.VIDEO)
                    AlbumPickerMediaType.VIDEO else AlbumPickerMediaType.PHOTO,
            mediaPath = albumMedia.mediaPath,
            videoThumbnailPath = albumMedia.videoThumbnailPath,
        )

    private fun createBannerItem(
        iconRes: Int,
        textRes: Int,
        iconTextSpacing: Int,
        iconIconSpacing: Int,
        onClick: () -> Unit,
    ): LinearLayout {
        val vPad = context.resources.getDimensionPixelSize(R.dimen.spacing_8)
        val banner =
            LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setBackgroundColor(theme.backgroundColorSecondary)
                setPadding(iconIconSpacing, vPad, iconIconSpacing, vPad)
                layoutParams =
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    )
                setOnClickListener { onClick() }
            }
        banner.addView(createBannerIcon(iconRes))
        banner.addView(createBannerText(textRes, iconTextSpacing))
        return banner
    }

    private fun createBannerIcon(iconRes: Int): ImageView {
        val s = AlbumPickerUtil.dpToPx(context, BANNER_ICON_SIZE_DP)
        return ImageView(context).apply {
            setImageResource(iconRes)
            setColorFilter(theme.textColorSecondary)
            layoutParams = LinearLayout.LayoutParams(s, s)
        }
    }

    private fun createBannerText(textRes: Int, marginStart: Int): TextView =
        TextView(context).apply {
            text = AlbumPickerCoreLanguage.getString(context, textRes)
            setTextColor(theme.textColorSecondary)
            textSize = theme.normalFontSize
            typeface = Typeface.DEFAULT_BOLD
            layoutParams =
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    .apply { this.marginStart = marginStart }
        }

    private fun showPermissionOverlay(type: PermissionOverlayType) {
        dismissPermissionOverlay()
        val parentFrame = contentView.parent as? FrameLayout ?: return
        val overlay = PermissionOverlayView(context, type)
        parentFrame.addView(overlay)
        permissionOverlay = overlay
        overlay.show()
    }

    private fun dismissPermissionOverlay() {
        val overlay = permissionOverlay ?: return
        (overlay.parent as? ViewGroup)?.removeView(overlay)
        permissionOverlay = null
    }
}
