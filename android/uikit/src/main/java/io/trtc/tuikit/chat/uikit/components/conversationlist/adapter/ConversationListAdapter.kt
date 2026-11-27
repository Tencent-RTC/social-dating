package io.trtc.tuikit.chat.uikit.components.conversationlist.adapter
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.text.style.ImageSpan
import android.util.TypedValue
import androidx.core.graphics.ColorUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.common.ChatDateTimeUtils
import io.trtc.tuikit.chat.uikit.components.common.ConversationIDUtil
import io.trtc.tuikit.chat.uikit.components.conversationlist.ui.ConversationSwipeItem
import io.trtc.tuikit.chat.uikit.components.conversationlist.ui.ConversationSwipeRowLayout
import io.trtc.tuikit.chat.uikit.components.conversationlist.utils.isUnread
import io.trtc.tuikit.chat.uikit.components.conversationlist.utils.needShowBadge
import io.trtc.tuikit.chat.uikit.components.conversationlist.utils.needShowNotReceiveIcon
import io.trtc.tuikit.chat.uikit.components.emojipicker.EmojiSpanHelper
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.CallStreamMediaType
import io.trtc.tuikit.chat.uikit.components.messagelist.utils.MessageListMessageSummaryFormatter
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.chat.uikit.components.widgets.Avatar
import io.trtc.tuikit.chat.uikit.components.widgets.SendingIndicatorView
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.GroupAtType
import io.trtc.tuikit.atomicxcore.api.conversation.ReceiveMessageOption
import io.trtc.tuikit.atomicxcore.api.message.MessageStatus

internal fun resolveConversationAvatarBadge(conversation: ConversationInfo): Avatar.AvatarBadge {
    val isReceiveMessage = conversation.receiveOption == ReceiveMessageOption.RECEIVE
    return when {
        conversation.isUnread && conversation.needShowBadge -> {
            val count = maxOf(conversation.unreadCount, 1)
            val badgeText = if (count > 99) "99+" else count.toString()
            Avatar.AvatarBadge.Text(badgeText)
        }
        !isReceiveMessage && conversation.isUnread -> Avatar.AvatarBadge.Dot
        else -> Avatar.AvatarBadge.None
    }
}

class ConversationListAdapter(
    private val context: Context,
    private val onItemClick: (ConversationInfo) -> Unit = {},
    private val onItemLongClick: (ConversationInfo, View) -> Unit = { _, _ -> },
    private val swipeItemsProvider: (ConversationInfo) -> List<ConversationSwipeItem> = { emptyList() },
    private val onSwipeOpened: (ConversationSwipeRowLayout) -> Unit = {},
    private val titleAccessory: ((ConversationInfo) -> View?)? = null
) : ListAdapter<ConversationInfo, ConversationListAdapter.ConversationViewHolder>(DIFF) {

    private val themeStore = ThemeStore.shared(context)
    private val colors: ColorTokens get() = themeStore.themeState.value.currentTheme.tokens.color
    private val summaryFormatter = MessageListMessageSummaryFormatter()

    /** Left-swipe actions on a row; the 消息 tab keeps only the long-press menu, so it turns this off. */
    var swipeEnabled: Boolean = true

    private fun swipeItems(conversation: ConversationInfo): List<ConversationSwipeItem> =
        if (swipeEnabled) swipeItemsProvider(conversation) else emptyList()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ConversationViewHolder {
        val itemView = ConversationSwipeRowLayout(parent.context)
        itemView.onOpened = onSwipeOpened
        itemView.layoutParams = RecyclerView.LayoutParams(
            RecyclerView.LayoutParams.MATCH_PARENT,
            dp2px(parent.context, 72f)
        )
        return ConversationViewHolder(itemView)
    }

    override fun onBindViewHolder(holder: ConversationViewHolder, position: Int) {
        val conversation = getItem(position)
        holder.bind(conversation)
    }

    override fun onBindViewHolder(
        holder: ConversationViewHolder,
        position: Int,
        payloads: MutableList<Any>
    ) {
        if (payloads.contains(PAYLOAD_THEME)) {
            holder.bindTheme(getItem(position))
        } else {
            super.onBindViewHolder(holder, position, payloads)
        }
    }

    fun notifyThemeChanged() {
        if (itemCount > 0) {
            notifyItemRangeChanged(0, itemCount, PAYLOAD_THEME)
        }
    }

    inner class ConversationViewHolder(
        private val swipeRow: ConversationSwipeRowLayout
    ) : RecyclerView.ViewHolder(swipeRow) {

        private val itemLayout: ConversationItemLayout get() = swipeRow.front

        fun bind(conversation: ConversationInfo) {
            val colors = this@ConversationListAdapter.colors

            swipeRow.closeImmediately()
            swipeRow.bindActions(swipeItems(conversation), colors)
            itemLayout.bindConversation(conversation, colors, context, summaryFormatter)
            itemLayout.setTitleAccessory(titleAccessory?.invoke(conversation))
            // A recycled row must not come back with the long-press highlight still on.
            itemLayout.setHighlighted(false, colors)

            itemLayout.setOnClickListener {
                onItemClick(conversation)
            }

            itemLayout.setOnLongClickListener {
                itemLayout.setHighlighted(true, colors)
                onItemLongClick(conversation, itemLayout)
                true
            }
        }

        fun bindTheme(conversation: ConversationInfo) {
            swipeRow.bindActions(swipeItems(conversation), colors)
            itemLayout.bindTheme(conversation, colors, context, summaryFormatter)
        }
    }

    companion object {
        private const val PAYLOAD_THEME = "conversation_list_theme"

        val DIFF = object : DiffUtil.ItemCallback<ConversationInfo>() {
            override fun areItemsTheSame(
                oldItem: ConversationInfo,
                newItem: ConversationInfo
            ): Boolean = oldItem.conversationID == newItem.conversationID

            override fun areContentsTheSame(
                oldItem: ConversationInfo,
                newItem: ConversationInfo
            ): Boolean = oldItem == newItem
        }
    }
}

class ConversationItemLayout(context: Context) : FrameLayout(context) {

    private val avatar: Avatar
    private val titleView: TextView
    private val titleRow: LinearLayout
    private val titleAccessorySlot: FrameLayout
    private val subtitleView: TextView
    private val timeView: TextView
    private val muteIcon: ImageView
    private val sendFailIcon: TextView
    private val sendingIndicator: SendingIndicatorView

    private val highlightOverlay = ColorDrawable(Color.TRANSPARENT)
    private val sendFailIconBackground = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
    }

    init {
        isClickable = true
        isFocusable = true
        clipChildren = false
        clipToPadding = false
        layoutDirection = View.LAYOUT_DIRECTION_LOCALE

        val contentRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            clipChildren = false
            clipToPadding = false
            setPadding(dp2px(context, 16f), 0, dp2px(context, 16f), 0)
            layoutParams = FrameLayout.LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT
            )
        }
        addView(contentRow)

        avatar = Avatar(context).apply {
            setSize(Avatar.AvatarSize.L)
        }
        contentRow.addView(avatar, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        val spacer1 = View(context)
        contentRow.addView(spacer1, LinearLayout.LayoutParams(dp2px(context, 12f), 0))

        val middleColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            layoutParams = LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        }
        contentRow.addView(middleColumn)

        titleView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            typeface = Typeface.DEFAULT
            textAlignment = View.TEXT_ALIGNMENT_VIEW_START
            textDirection = View.TEXT_DIRECTION_LOCALE
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        titleRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        }
        middleColumn.addView(titleRow, LinearLayout.LayoutParams(
            LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT
        ))
        titleRow.addView(titleView, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        titleAccessorySlot = FrameLayout(context).apply { visibility = GONE }
        titleRow.addView(titleAccessorySlot, LinearLayout.LayoutParams(
            LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT
        ).apply { marginStart = dp2px(context, 6f) })
        // Keeps the title and its tags left-aligned; long nicknames are capped by [setTitleAccessory] instead of
        // pushing the tags to the right edge of the row.
        titleRow.addView(View(context), LinearLayout.LayoutParams(0, 0, 1f))

        val spacerTitle = View(context)
        middleColumn.addView(spacerTitle, LinearLayout.LayoutParams(0, dp2px(context, 2f)))

        val subtitleRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        }
        middleColumn.addView(subtitleRow, LinearLayout.LayoutParams(
            LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT
        ))

        sendFailIcon = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            includeFontPadding = false
            text = "!"
            visibility = GONE
            background = sendFailIconBackground
        }
        subtitleRow.addView(sendFailIcon, LinearLayout.LayoutParams(
            dp2px(context, 14f), dp2px(context, 14f)
        ).apply { marginEnd = dp2px(context, 4f) })

        sendingIndicator = SendingIndicatorView(context).apply {
            visibility = GONE
        }
        subtitleRow.addView(sendingIndicator, LinearLayout.LayoutParams(
            dp2px(context, 12f), dp2px(context, 12f)
        ).apply { marginEnd = dp2px(context, 4f) })

        subtitleView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            textAlignment = View.TEXT_ALIGNMENT_VIEW_START
            textDirection = View.TEXT_DIRECTION_LOCALE
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        subtitleRow.addView(subtitleView, LinearLayout.LayoutParams(
            0, LayoutParams.WRAP_CONTENT, 1f
        ))

        val spacerMiddle = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp2px(context, 16f), 0)
        }
        contentRow.addView(spacerMiddle)

        val rightColumn = FrameLayout(context).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        }
        contentRow.addView(rightColumn, LinearLayout.LayoutParams(
            LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT
        ))

        timeView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            textAlignment = View.TEXT_ALIGNMENT_VIEW_END
            textDirection = View.TEXT_DIRECTION_LOCALE
        }
        rightColumn.addView(timeView, FrameLayout.LayoutParams(
            LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END
        ).apply { topMargin = dp2px(context, 13f) })

        muteIcon = ImageView(context).apply {
            visibility = GONE
            setImageDrawable(context.getDrawable(R.drawable.conversation_list_not_receive_icon)?.apply {
                isAutoMirrored = true
            })
        }
        rightColumn.addView(muteIcon, FrameLayout.LayoutParams(
            dp2px(context, 16f), dp2px(context, 16f), Gravity.BOTTOM or Gravity.END
        ).apply { bottomMargin = dp2px(context, 13f) })

        foreground = highlightOverlay
    }

    fun bindConversation(
        conversation: ConversationInfo,
        colors: ColorTokens,
        context: Context,
        summaryFormatter: MessageListMessageSummaryFormatter = MessageListMessageSummaryFormatter()
    ) {
        avatar.setContent(
            Avatar.AvatarContent.Image(
                url = conversation.avatarURL,
                fallbackName = conversation.title ?: conversation.conversationID
            )
        )

        bindAvatarBadge(conversation)

        titleView.text = conversation.title ?: conversation.conversationID
        timeView.text = ChatDateTimeUtils.formatConversationListTime(conversation.lastMessage?.timestamp)

        bindTheme(conversation, colors, context, summaryFormatter)
    }

    fun setTitleAccessory(view: View?) {
        titleAccessorySlot.removeAllViews()
        if (view != null) titleAccessorySlot.addView(view)
        titleAccessorySlot.visibility = if (view == null) GONE else VISIBLE
        // The tags sit right after the nickname, so the nickname must ellipsize before it runs into them.
        titleView.maxWidth = Int.MAX_VALUE
        if (view != null) {
            titleRow.post {
                val available = titleRow.width - titleAccessorySlot.width - dp2px(context, 6f)
                if (available > 0 && available != titleView.maxWidth) titleView.maxWidth = available
            }
        }
    }

    fun bindTheme(
        conversation: ConversationInfo,
        colors: ColorTokens,
        context: Context,
        summaryFormatter: MessageListMessageSummaryFormatter = MessageListMessageSummaryFormatter()
    ) {
        setBackgroundColor(
            if (conversation.isPinned) colors.bgColorInput else colors.bgColorTopBar
        )
        titleView.setTextColor(colors.textColorPrimary)
        subtitleView.setTextColor(colors.textColorSecondary)
        val rawSubtitle = buildSubtitle(conversation, colors, context, summaryFormatter)
        val fallbackSubtitle = buildSubtitle(
            conversation, colors, context, summaryFormatter, EmojiSpanHelper::replaceEmojiKeysWithNames
        )
        val bindToken = "${conversation.conversationID}|${conversation.lastMessage?.msgID.orEmpty()}|$rawSubtitle|${subtitleView.textSize}"
        subtitleView.setTag(R.id.emoji_span_bind_token_tag, bindToken)
        subtitleView.text = fallbackSubtitle
        EmojiSpanHelper.applyEmojiSpans(context, rawSubtitle, subtitleView.textSize, subtitleView) { spanned ->
            if (subtitleView.getTag(R.id.emoji_span_bind_token_tag) == bindToken) {
                subtitleView.text = spanned
            }
        }
        timeView.setTextColor(colors.textColorSecondary)
        bindMuteIcon(conversation, colors)
        bindSendStatus(conversation, colors)
    }

    /**
     * Long-press highlight. A fixed black wash is invisible on a dark surface, so the overlay follows the theme:
     * white in dark mode, black in light mode.
     */
    fun setHighlighted(highlighted: Boolean, colors: ColorTokens) {
        highlightOverlay.color = if (highlighted) pressedOverlay(colors) else Color.TRANSPARENT
    }

    private fun pressedOverlay(colors: ColorTokens): Int {
        val dark = ColorUtils.calculateLuminance(colors.bgColorTopBar) < 0.5
        return if (dark) Color.argb(34, 255, 255, 255) else Color.argb(20, 0, 0, 0)
    }

    private fun bindAvatarBadge(conversation: ConversationInfo) {
        avatar.setBadge(resolveConversationAvatarBadge(conversation))
    }

    private fun bindMuteIcon(conversation: ConversationInfo, colors: ColorTokens) {
        if (conversation.needShowNotReceiveIcon) {
            muteIcon.setColorFilter(colors.textColorDisable, PorterDuff.Mode.SRC_IN)
            muteIcon.visibility = VISIBLE
        } else {
            muteIcon.visibility = GONE
        }
    }

    private fun bindSendStatus(conversation: ConversationInfo, colors: ColorTokens) {
        val lastMsg = conversation.lastMessage
        when (lastMsg?.status) {
            MessageStatus.SEND_FAIL, MessageStatus.VIOLATION -> {
                sendFailIcon.visibility = VISIBLE
                sendFailIcon.setTextColor(colors.textColorButton)
                sendFailIconBackground.setColor(colors.textColorError)
                sendingIndicator.stop()
                sendingIndicator.visibility = GONE
            }
            MessageStatus.SENDING -> {
                sendFailIcon.visibility = GONE
                sendingIndicator.visibility = VISIBLE
                sendingIndicator.start()
            }
            else -> {
                sendFailIcon.visibility = GONE
                sendingIndicator.stop()
                sendingIndicator.visibility = GONE
            }
        }
    }

    private fun buildSubtitle(
        conversation: ConversationInfo,
        colors: ColorTokens,
        context: Context,
        summaryFormatter: MessageListMessageSummaryFormatter,
        transform: (String) -> String = { it }
    ): CharSequence {
        val atTagText = buildAtTagText(conversation, context)
        val draft = conversation.draft
        if (!draft.isNullOrEmpty()) {
            val draftPrefix = context.getString(R.string.conversation_list_draft_prefix)
            return SpannableStringBuilder().apply {
                appendErrorText(colors, atTagText)
                appendErrorText(colors, draftPrefix)
                append(" ")
                append(transform(draft))
            }
        }

        val defaultSubtitle = transform(getMessageAbstract(conversation, context, summaryFormatter))
        val callMediaType = summaryFormatter.resolveCallStreamMediaType(
            context, conversation.lastMessage, conversation.conversationID
        )
        val subtitleWithCallIcon: CharSequence = if (callMediaType != null) {
            SpannableStringBuilder().apply {
                appendCallIconSpan(context, colors, callMediaType)
                append(defaultSubtitle)
            }
        } else {
            defaultSubtitle
        }

        if (atTagText.isNotEmpty()) {
            return SpannableStringBuilder().apply {
                appendErrorText(colors, atTagText)
                append(" ")
                append(subtitleWithCallIcon)
            }
        }

        if (conversation.receiveOption != ReceiveMessageOption.RECEIVE && conversation.unreadCount > 0) {
            return SpannableStringBuilder().apply {
                append("[")
                append(conversation.unreadCount.toString())
                append(context.getString(R.string.conversation_list_message_count_unit))
                append("] ")
                append(subtitleWithCallIcon)
            }
        }

        return subtitleWithCallIcon
    }

    private fun SpannableStringBuilder.appendCallIconSpan(
        context: Context,
        colors: ColorTokens,
        mediaType: CallStreamMediaType
    ) {
        val iconRes = when (mediaType) {
            CallStreamMediaType.VOICE -> R.drawable.conversation_list_call_audio_icon
            CallStreamMediaType.VIDEO -> R.drawable.conversation_list_call_video_icon
            else -> return
        }
        val drawable = ContextCompat.getDrawable(context, iconRes)?.mutate() ?: return
        drawable.setTint(colors.textColorSecondary)
        val heightPx = dp2px(context, 12f)
        val widthPx = heightPx
        val marginPx = dp2px(context, 4f)
        val insetDrawable = InsetDrawable(drawable, 0, 0, marginPx, 0)
        insetDrawable.setBounds(0, 0, widthPx + marginPx, heightPx)
        val start = length
        append(" ")
        setSpan(VerticallyCenteredImageSpan(insetDrawable), start, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private class VerticallyCenteredImageSpan(drawable: Drawable) : ImageSpan(drawable) {
        override fun draw(
            canvas: Canvas,
            text: CharSequence?,
            start: Int,
            end: Int,
            x: Float,
            top: Int,
            y: Int,
            bottom: Int,
            paint: Paint
        ) {
            val icon = drawable
            val fm = paint.fontMetricsInt
            val textCenter = y + (fm.ascent + fm.descent) / 2
            val transY = textCenter - icon.bounds.height() / 2
            canvas.save()
            canvas.translate(x, transY.toFloat())
            icon.draw(canvas)
            canvas.restore()
        }
    }

    private fun SpannableStringBuilder.appendErrorText(colors: ColorTokens, text: String) {
        if (text.isEmpty()) return
        val start = length
        append(text)
        setSpan(
            ForegroundColorSpan(colors.textColorError),
            start,
            length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    private fun getMessageAbstract(
        conversation: ConversationInfo,
        context: Context,
        summaryFormatter: MessageListMessageSummaryFormatter
    ): String {
        val messageInfo = conversation.lastMessage ?: return ""
        return summaryFormatter.format(context, messageInfo, conversation.conversationID)
    }

    private fun buildAtTagText(conversation: ConversationInfo, context: Context): String {
        if (conversation.unreadCount <= 0) return ""
        if (!ConversationIDUtil.isGroup(conversation.conversationID)) return ""

        val groupAtInfoList = conversation.groupAtInfoList ?: return ""
        if (groupAtInfoList.isEmpty()) return ""

        val atAllPrefix = context.getString(R.string.conversation_list_at_all_prefix)
        val atMePrefix = context.getString(R.string.conversation_list_at_me_prefix)

        var hasAtAll = false
        var hasAtMe = false

        for (atInfo in groupAtInfoList) {
            when (atInfo.atType) {
                GroupAtType.AT_ME -> hasAtMe = true
                GroupAtType.AT_ALL -> hasAtAll = true
                GroupAtType.AT_ALL_AT_ME -> {
                    hasAtAll = true
                    hasAtMe = true
                }
                else -> Unit
            }
        }

        return buildString {
            if (hasAtAll) append(atAllPrefix)
            if (hasAtMe) append(atMePrefix)
        }
    }
}

fun dp2px(context: Context, dpValue: Float): Int {
    return TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, dpValue, context.resources.displayMetrics
    ).toInt()
}

