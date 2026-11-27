package io.trtc.tuikit.chat.uikit.components.messagelist.ui.messagerenderers
import android.content.Context
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.drawable.GradientDrawable
import androidx.core.graphics.ColorUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.common.AtomicCallEventPublisher
import io.trtc.tuikit.chat.uikit.components.common.RtlUtils
import io.trtc.tuikit.chat.uikit.components.messagelist.config.MessageListConfigProtocol
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderConfig
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderer
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallProtocolType
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallMessageModel
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallMessageParser
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallStreamMediaType
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.getCallMessageDisplayString
import io.trtc.tuikit.chat.uikit.components.messagelist.viewmodel.MessageListViewModel
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo

/**
 * Call record bubble (design `callbubble`, board F / S3): 10x14 padding, 10 gap, 16 radius, a 20dp
 * phone / video glyph and a two-line meta block (title 14/20, sub 10/14 "tap to call back").
 * Own = `brandGradient` with `textColorButton`; peer = `bgColorBubbleReciprocal` with a primary-coloured glyph.
 *
 * Only the presentation changed: the title is still the SDK's fixed-format display string and the
 * message payload / businessID / call-back behaviour are untouched (docs/04 call message skin).
 */
class CallingMessageRenderer : MessageRenderer {

    companion object {
        private const val TAG_TITLE = "calling_title"
        private const val TAG_SUB = "calling_sub"
        private const val TAG_ICON = "calling_icon"
        private const val BUBBLE_RADIUS_DP = 16f
    }

    /** The renderer draws its own gradient / peer bubble with equal corner radii. */
    override val renderConfig: MessageRenderConfig
        get() = MessageRenderConfig(showMessageMeta = true, useDefaultBubble = false)

    override fun createView(context: Context, parent: ViewGroup): View {
        val density = context.resources.displayMetrics.density
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            gravity = Gravity.CENTER_VERTICAL
            setPadding((14 * density).toInt(), (10 * density).toInt(), (14 * density).toInt(), (10 * density).toInt())
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }
        val icon = ImageView(context).apply {
            tag = TAG_ICON
            visibility = View.GONE
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        container.addView(icon, LinearLayout.LayoutParams((20 * density).toInt(), (20 * density).toInt()))

        val meta = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val title = TextView(context).apply {
            tag = TAG_TITLE
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            includeFontPadding = false
            setLineSpacing((20 * density) - textSize, 1f)
            maxLines = 2
        }
        val sub = TextView(context).apply {
            tag = TAG_SUB
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            includeFontPadding = false
            setLineSpacing((14 * density) - textSize, 1f)
            maxLines = 1
        }
        meta.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        meta.addView(
            sub,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = (2 * density).toInt() }
        )
        container.addView(
            meta,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { marginStart = (10 * density).toInt() }
        )
        return container
    }

    override fun bindView(
        view: View,
        message: MessageInfo,
        viewModel: MessageListViewModel,
        config: MessageListConfigProtocol,
        colors: ColorTokens
    ) {
        val container = view as LinearLayout
        val title = container.findViewWithTag<TextView>(TAG_TITLE)
        val sub = container.findViewWithTag<TextView>(TAG_SUB)
        val icon = container.findViewWithTag<ImageView>(TAG_ICON)

        val callModel = CallMessageParser.parse(message)
        if (callModel == null) {
            title.text = ""
            sub.visibility = View.GONE
            icon.visibility = View.GONE
            container.background = null
            container.setOnClickListener(null)
            return
        }

        val isSelf = message.isSentBySelf
        val radius = BUBBLE_RADIUS_DP * container.resources.displayMetrics.density
        container.background = if (isSelf) {
            GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(colors.buttonColorPrimaryDefault, colors.tagColorLevel4)
            ).apply { cornerRadius = radius }
        } else {
            GradientDrawable().apply {
                cornerRadius = radius
                setColor(colors.bgColorBubbleReciprocal)
            }
        }

        title.text = getCallMessageDisplayString(context = title.context, message = message, callModel = callModel)
        val missed = !isSelf && !callModel.isCaller &&
            (callModel.protocolType == CallProtocolType.CANCEL || callModel.protocolType == CallProtocolType.TIMEOUT)
        val titleColor = when {
            isSelf -> colors.textColorButton
            missed -> colors.textColorError
            else -> colors.textColorPrimary
        }
        title.setTextColor(titleColor)

        val iconRes = when (callModel.streamMediaType) {
            CallStreamMediaType.VOICE -> R.drawable.message_callbubble_phone
            CallStreamMediaType.VIDEO -> R.drawable.message_callbubble_video
            else -> 0
        }
        if (iconRes != 0) {
            icon.visibility = View.VISIBLE
            icon.setImageResource(iconRes)
            icon.colorFilter = PorterDuffColorFilter(
                if (isSelf) colors.textColorButton else colors.buttonColorPrimaryDefault, PorterDuff.Mode.SRC_IN
            )
        } else {
            icon.visibility = View.GONE
        }

        val canReCall = callModel.streamMediaType == CallStreamMediaType.VOICE ||
            callModel.streamMediaType == CallStreamMediaType.VIDEO
        if (canReCall) {
            sub.visibility = View.VISIBLE
            sub.text = sub.context.getString(R.string.message_list_call_tap_to_callback)
            sub.setTextColor(
                if (isSelf) ColorUtils.setAlphaComponent(colors.textColorButton, (255 * 0.88f).toInt()) else colors.textColorSecondary
            )
            container.isClickable = true
            container.setOnClickListener { reInitiateCall(message, callModel) }
        } else {
            sub.visibility = View.GONE
            container.setOnClickListener(null)
        }
    }

    private fun reInitiateCall(
        message: MessageInfo,
        callModel: CallMessageModel
    ) {
        val targetUserId = if (callModel.isCaller) {
            callModel.inviteeList.firstOrNull { it.isNotBlank() } ?: message.to.trim()
        } else {
            callModel.caller.trim()
        }
        if (targetUserId.isBlank()) {
            return
        }
        val mediaType = when (callModel.streamMediaType) {
            CallStreamMediaType.VIDEO -> AtomicCallEventPublisher.MEDIA_TYPE_VIDEO
            else -> AtomicCallEventPublisher.MEDIA_TYPE_AUDIO
        }
        AtomicCallEventPublisher.publishStartCall(
            participantIds = listOf(targetUserId),
            mediaType = mediaType
        )
    }
}

internal enum class CallMessageContentPart {
    ICON,
    TEXT
}

internal object CallMessageDisplayPolicy {
    fun contentOrder(isSelf: Boolean, isRtl: Boolean = false): List<CallMessageContentPart> {
        return if (isSelf xor isRtl) {
            listOf(CallMessageContentPart.TEXT, CallMessageContentPart.ICON)
        } else {
            listOf(CallMessageContentPart.ICON, CallMessageContentPart.TEXT)
        }
    }

    fun shouldShowOutsideUnreadDot(
        isSelf: Boolean,
        isShowUnreadPoint: Boolean
    ): Boolean {
        return isShowUnreadPoint && !isSelf
    }

    fun shouldMirrorCallIcon(
        isSelf: Boolean,
        streamMediaType: CallStreamMediaType,
        isRtl: Boolean = false,
    ): Boolean {
        val isCallMedia = streamMediaType == CallStreamMediaType.VIDEO ||
            streamMediaType == CallStreamMediaType.VOICE
        return isCallMedia && ((!isSelf) xor isRtl)
    }
}
