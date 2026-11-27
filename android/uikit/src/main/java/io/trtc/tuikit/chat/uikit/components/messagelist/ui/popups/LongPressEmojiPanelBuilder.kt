package io.trtc.tuikit.chat.uikit.components.messagelist.ui.popups
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.bumptech.glide.Glide
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.emojipicker.EmojiManager
import io.trtc.tuikit.chat.uikit.components.emojipicker.RecentEmojiManager
import io.trtc.tuikit.chat.uikit.components.emojipicker.model.Emoji
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.reactions.MessageReactionPanelPolicy
import io.trtc.tuikit.chat.uikit.components.messagelist.viewmodel.MessageListViewModel
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import kotlin.math.roundToInt

internal class LongPressEmojiPanelBuilder(
    private val context: Context,
    private val density: Float,
    private val colors: ColorTokens,
    private val message: MessageInfo,
    private val viewModel: MessageListViewModel,
    private val onDismiss: () -> Unit,
    private val onBack: (LongPressPanelLevel) -> Unit,
    private val onShowAllEmoji: () -> Unit
) {

    fun totalHeight(level: LongPressPanelLevel): Int {
        return LongPressDimens.emojiPanelTotalHeight(level, density)
    }

    fun build(cardWidth: Int, level: LongPressPanelLevel): View {
        val bodyHeight = LongPressDimens.emojiPanelBodyHeight(level, density)
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(cardWidth, totalHeight(level))
            addView(
                buildHeader(level),
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    LongPressDimens.emojiPanelHeaderHeight(density)
                )
            )
            addView(
                buildDivider(),
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    LongPressDimens.emojiPanelDividerHeight()
                ).apply {
                    marginStart = LongPressDimens.emojiPanelDividerMargin(density)
                    marginEnd = LongPressDimens.emojiPanelDividerMargin(density)
                }
            )
            addView(
                buildBody(level),
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, bodyHeight)
            )
        }
    }

    private fun buildHeader(level: LongPressPanelLevel): View {
        return FrameLayout(context).apply {
            setPadding(
                LongPressDimens.emojiPanelHeaderStartPadding(density),
                0,
                LongPressDimens.emojiPanelHeaderEndPadding(density),
                0
            )
            addView(
                buildBackButton(level),
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    LongPressDimens.emojiPanelBackHeight(density),
                    Gravity.START or Gravity.CENTER_VERTICAL
                )
            )
            addView(
                TextView(context).apply {
                    text = context.getString(
                        if (level == LongPressPanelLevel.ALL) {
                            R.string.message_list_reaction_all_title
                        } else {
                            R.string.message_list_reaction_recent_used
                        }
                    )
                    setTextColor(colors.textColorTertiary)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                },
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.END or Gravity.CENTER_VERTICAL
                )
            )
        }
    }

    private fun buildBackButton(level: LongPressPanelLevel): View {
        val iconSize = LongPressDimens.emojiPanelBackIconSize(density)
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(4.dp, 0, 10.dp, 0)
            isClickable = true
            isFocusable = true
            contentDescription = context.getString(R.string.message_list_reaction_back)
            background = LongPressDrawables.createBackButtonRipple(colors, density)
            setOnClickListener { onBack(level) }
            addView(
                ImageView(context).apply {
                    setImageResource(R.drawable.message_list_menu_chevron_down_icon)
                    imageTintList = ColorStateList.valueOf(colors.textColorSecondary)
                    rotation = 90f
                    scaleType = ImageView.ScaleType.FIT_CENTER
                },
                LinearLayout.LayoutParams(iconSize, iconSize)
            )
            addView(
                TextView(context).apply {
                    text = context.getString(R.string.message_list_reaction_back)
                    setTextColor(colors.textColorSecondary)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setPadding(2.dp, 0, 0, 0)
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }
    }

    private fun buildDivider(): View {
        return View(context).apply {
            setBackgroundColor(colors.strokeColorPrimary)
        }
    }

    private fun buildBody(level: LongPressPanelLevel): View {
        val grid = buildGrid(level)
        if (level != LongPressPanelLevel.ALL) {
            return grid
        }
        return ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            isFillViewport = false
            addView(
                grid,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }
    }

    private fun buildGrid(level: LongPressPanelLevel): View {
        val columns = MessageReactionPanelPolicy.COLUMNS
        val cells: List<View> = if (level == LongPressPanelLevel.ALL) {
            EmojiManager.reactionEmojiListForPicker().map { buildEmojiCell(it) }
        } else {
            getRecentEmojis().map { buildEmojiCell(it) } + buildMoreCell()
        }
        val cellSize = LongPressDimens.emojiCellSize(density)
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                LongPressDimens.emojiPanelHorizontalPadding(density),
                LongPressDimens.emojiPanelVerticalPadding(density),
                LongPressDimens.emojiPanelHorizontalPadding(density),
                LongPressDimens.emojiPanelVerticalPadding(density)
            )
            cells.chunked(columns).forEach { rowCells ->
                addView(
                    LinearLayout(context).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.START
                        rowCells.forEach { cell ->
                            addView(cell, LinearLayout.LayoutParams(cellSize, cellSize))
                        }
                    },
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        cellSize
                    )
                )
            }
        }
    }

    private fun buildEmojiCell(emoji: Emoji): View {
        val cellSize = LongPressDimens.emojiCellSize(density)
        val imageSize = LongPressDimens.emojiImageSize(density)
        val operateColor = colors.floatingColorOperate
        val isReacted = message.reactionList.any {
            it.reactionID == emoji.key && it.reactedByMyself
        }
        return FrameLayout(context).apply {
            background = if (isReacted) {
                GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(operateColor)
                }
            } else {
                LongPressDrawables.createEmojiCellRipple(colors, cellSize)
            }
            contentDescription = emoji.emojiName
            isClickable = true
            isFocusable = true
            setOnClickListener {
                if (isReacted) {
                    viewModel.removeMessageReaction(message, emoji.key)
                } else {
                    viewModel.addMessageReaction(message, emoji.key)
                    EmojiManager.reactionEmojiGroup?.let {
                        RecentEmojiManager.updateRecentEmoji(it.id, emoji.key)
                    }
                }
                onDismiss()
            }
            addView(
                ImageView(context).apply {
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    val drawable = EmojiManager.getCachedEmojiDrawable(emoji.key)
                    if (drawable != null) {
                        setImageDrawable(drawable)
                    } else {
                        Glide.with(this).load(emoji.emojiUrl).into(this)
                    }
                },
                FrameLayout.LayoutParams(imageSize, imageSize, Gravity.CENTER)
            )
        }
    }

    private fun buildMoreCell(): View {
        val cellSize = LongPressDimens.emojiCellSize(density)
        val circleSize = LongPressDimens.emojiMoreCircleSize(density)
        val operateColor = colors.floatingColorOperate
        return FrameLayout(context).apply {
            background = LongPressDrawables.createEmojiCellRipple(colors, cellSize)
            contentDescription = context.getString(R.string.message_list_reaction_expand)
            isClickable = true
            isFocusable = true
            setOnClickListener { onShowAllEmoji() }
            addView(
                ImageView(context).apply {
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(operateColor)
                    }
                    setImageResource(R.drawable.message_list_menu_chevron_down_icon)
                    imageTintList = ColorStateList.valueOf(colors.textColorSecondary)
                    setPadding(6.dp, 6.dp, 6.dp, 6.dp)
                    scaleType = ImageView.ScaleType.FIT_CENTER
                },
                FrameLayout.LayoutParams(circleSize, circleSize, Gravity.CENTER)
            )
        }
    }

    private fun getRecentEmojis(): List<Emoji> {
        val allEmojis = EmojiManager.reactionEmojiListForPicker()
        if (allEmojis.isEmpty()) {
            return emptyList()
        }
        val emojiMap = allEmojis.associateBy { it.key }
        val orderedKeys = mutableListOf<String>()
        orderedKeys += message.reactionList
            .filter { it.reactedByMyself }
            .map { it.reactionID }
        EmojiManager.reactionEmojiGroup?.let { group ->
            orderedKeys += RecentEmojiManager.getRecentEmojiList(group.id)
        }
        orderedKeys += allEmojis.map { it.key }

        val result = mutableListOf<Emoji>()
        val usedKeys = mutableSetOf<String>()
        for (key in orderedKeys) {
            val emoji = emojiMap[key] ?: continue
            if (!usedKeys.add(key)) {
                continue
            }
            result.add(emoji)
            if (result.size >= MessageReactionPanelPolicy.RECENT_COUNT) {
                break
            }
        }
        return result
    }

    private val Int.dp: Int
        get() = (this * density).roundToInt()
}
