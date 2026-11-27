package io.trtc.tuikit.chat.uikit.components.messagelist.ui.messagerenderers
import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.os.Build
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.resource.bitmap.CenterCrop
import com.bumptech.glide.request.RequestOptions
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.messagelist.config.MessageListConfigProtocol
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderConfig
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderer
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.formatSmartTime
import io.trtc.tuikit.chat.uikit.components.messagelist.viewmodel.MessageListViewModel
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import io.trtc.tuikit.atomicxcore.api.message.MessageStatus
import io.trtc.tuikit.atomicxcore.api.message.VideoMessagePayload

/**
 * Video bubble per design board F (prototype `.bubble--video`): a fixed 202x136dp frame (design 176x118
 * scaled by 15%) with 16dp corners, a center-cropped snapshot, a 46dp translucent play badge in the middle
 * and a 20dp duration pill at (133, 107). Tap-to-open and violation handling are unchanged.
 */
class VideoMessageRenderer : MessageRenderer {

    companion object {
        private const val TAG_SNAPSHOT = "snapshot"
        private const val TAG_DURATION = "duration"
    }

    override val renderConfig: MessageRenderConfig
        get() = MessageRenderConfig(showMessageMeta = true, useDefaultBubble = false)

    override fun createView(context: Context, parent: ViewGroup): View {
        val density = context.resources.displayMetrics.density
        val cornerRadiusPx = MediaBubbleMetrics.VIDEO_RADIUS_DP * density
        val container = FrameLayout(context).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            layoutParams = FrameLayout.LayoutParams(
                (MediaBubbleMetrics.VIDEO_WIDTH_DP * density).toInt(),
                (MediaBubbleMetrics.VIDEO_HEIGHT_DP * density).toInt()
            )
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, cornerRadiusPx)
                }
            }
            clipToOutline = true
        }

        val imageView = ImageView(context).apply {
            scaleType = VideoSnapshotImageLoadPolicy.scaleType
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            tag = TAG_SNAPSHOT
        }
        container.addView(imageView)

        val badgePx = (MediaBubbleMetrics.PLAY_BADGE_DP * density).toInt()
        val badge = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(MediaBubbleMetrics.PLAY_BADGE_FILL)
                setStroke(
                    (MediaBubbleMetrics.PLAY_BADGE_RING_DP * density).toInt().coerceAtLeast(1),
                    MediaBubbleMetrics.PLAY_BADGE_RING
                )
            }
            layoutParams = FrameLayout.LayoutParams(badgePx, badgePx, Gravity.CENTER)
        }
        val glyphPx = (MediaBubbleMetrics.PLAY_GLYPH_DP * density).toInt()
        badge.addView(
            PlayGlyphView(context).apply { color = Color.WHITE },
            FrameLayout.LayoutParams(glyphPx, glyphPx, Gravity.CENTER)
        )
        container.addView(badge)

        val pillPadding = (MediaBubbleMetrics.DURATION_PADDING_DP * density).toInt()
        val durationView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, MediaBubbleMetrics.DURATION_TEXT_SP)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER_VERTICAL
            includeFontPadding = false
            maxLines = 1
            setPadding(pillPadding, 0, pillPadding, 0)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = MediaBubbleMetrics.DURATION_RADIUS_DP * density
                setColor(MediaBubbleMetrics.DURATION_FILL)
            }
            tag = TAG_DURATION
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                (MediaBubbleMetrics.DURATION_HEIGHT_DP * density).toInt(),
                Gravity.TOP or Gravity.LEFT
            ).apply {
                leftMargin = (MediaBubbleMetrics.DURATION_LEFT_DP * density).toInt()
                topMargin = (MediaBubbleMetrics.DURATION_TOP_DP * density).toInt()
            }
        }
        container.addView(durationView)

        return container
    }

    override fun bindView(
        view: View,
        message: MessageInfo,
        viewModel: MessageListViewModel,
        config: MessageListConfigProtocol,
        colors: ColorTokens
    ) {
        val container = view as FrameLayout
        val imageView = container.findViewWithTag<ImageView>(TAG_SNAPSHOT)
        val durationView = container.findViewWithTag<TextView>(TAG_DURATION)

        val payload = message.messagePayload as? VideoMessagePayload
        val density = view.context.resources.displayMetrics.density
        val portrait = MediaBubbleMetrics.isPortrait(
            payload?.videoSnapshotWidth ?: 0,
            payload?.videoSnapshotHeight ?: 0,
        )
        val frame = MediaBubbleMetrics.videoFrame(
            payload?.videoSnapshotWidth ?: 0,
            payload?.videoSnapshotHeight ?: 0,
        )
        container.layoutParams = container.layoutParams.apply {
            width = (frame.widthDp * density).toInt()
            height = (frame.heightDp * density).toInt()
        }
        durationView.layoutParams = (durationView.layoutParams as FrameLayout.LayoutParams).apply {
            leftMargin = (MediaBubbleMetrics.durationLeftDp(portrait) * density).toInt()
            topMargin = (MediaBubbleMetrics.durationTopDp(portrait) * density).toInt()
        }

        val snapshotPath = payload?.videoSnapshotPath?.takeIf { it.isNotBlank() }
            ?: payload?.videoSnapshotURL?.takeIf { it.isNotBlank() }
        VideoSnapshotImageLoader.load(view.context, imageView, snapshotPath)

        val durationSeconds = payload?.videoDuration ?: 0
        durationView.text = formatSmartTime(durationSeconds)

        if (message.status == MessageStatus.VIOLATION) {
            view.setOnClickListener(null)
            view.isClickable = false
        } else {
            view.isClickable = true
            view.setOnClickListener {
                viewModel.showImage(view.context, message)
            }
        }
    }
}

internal object VideoSnapshotImageLoadPolicy {
    val scaleType: ImageView.ScaleType = ImageView.ScaleType.CENTER_CROP
}

private object VideoSnapshotImageLoader {
    fun load(context: Context, imageView: ImageView, snapshotPath: String?) {
        imageView.scaleType = VideoSnapshotImageLoadPolicy.scaleType
        if (snapshotPath.isNullOrBlank()) {
            imageView.setImageResource(R.drawable.message_list_image_error_image)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1
            && context is Activity
            && (context.isFinishing || context.isDestroyed)
        ) {
            return
        }
        Glide.with(context.applicationContext)
            .load(snapshotPath)
            .apply(
                RequestOptions()
                    .transform(CenterCrop())
                    .placeholder(R.drawable.message_list_image_error_image)
                    .error(R.drawable.message_list_image_error_image)
            )
            .into(imageView)
    }
}
