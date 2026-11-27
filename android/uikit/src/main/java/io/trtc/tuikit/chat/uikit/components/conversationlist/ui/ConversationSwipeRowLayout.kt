package io.trtc.tuikit.chat.uikit.components.conversationlist.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.chat.uikit.components.conversationlist.adapter.ConversationItemLayout
import io.trtc.tuikit.chat.uikit.components.conversationlist.model.ConversationActionIDs
import kotlin.math.abs

data class ConversationSwipeItem(
    val id: String,
    val title: String,
    val iconRes: Int,
    val onClick: () -> Unit,
)

/**
 * Swipe-to-reveal row: three 72dp actions (pin / mute / delete) hide behind the conversation
 * item. Dragging the item towards the start edge reveals them, matching the prototype
 * `.conv-swipe`.
 */
class ConversationSwipeRowLayout(context: Context) : FrameLayout(context) {

    val front: ConversationItemLayout = ConversationItemLayout(context)

    var onOpened: ((ConversationSwipeRowLayout) -> Unit)? = null

    private val actionsContainer = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        visibility = View.INVISIBLE
    }
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val density = context.resources.displayMetrics.density

    private var revealWidth = 0
    private var progress = 0f
    private var downX = 0f
    private var downY = 0f
    private var startProgress = 0f
    private var dragging = false
    private var tapToClose = false
    private var animator: ValueAnimator? = null

    val isOpen: Boolean get() = revealWidth > 0 && progress >= revealWidth

    private val direction: Int
        get() = if (layoutDirection == View.LAYOUT_DIRECTION_RTL) 1 else -1

    init {
        layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        clipChildren = true
        addView(
            actionsContainer,
            LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.END)
        )
        addView(front, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    fun bindActions(items: List<ConversationSwipeItem>, colors: ColorTokens) {
        actionsContainer.removeAllViews()
        val width = (ConversationMenuSpec.SWIPE_ACTION_WIDTH_DP * density).toInt()
        items.forEach { item ->
            actionsContainer.addView(buildAction(item, colors), LinearLayout.LayoutParams(width, ViewGroup.LayoutParams.MATCH_PARENT))
        }
        revealWidth = width * items.size
        if (revealWidth == 0) {
            closeImmediately()
        }
        applyProgress(progress.coerceAtMost(revealWidth.toFloat()))
    }

    fun close(animate: Boolean = true) {
        if (progress == 0f) return
        if (animate) animateTo(0f) else closeImmediately()
    }

    fun closeImmediately() {
        animator?.cancel()
        applyProgress(0f)
    }

    private fun buildAction(item: ConversationSwipeItem, colors: ColorTokens): View {
        val (bg, fg) = when (item.id) {
            ConversationActionIDs.PIN -> colors.buttonColorSecondaryDefault to colors.textColorPrimary
            ConversationActionIDs.MUTE -> colors.bgColorFunction to colors.textColorPrimary
            ConversationActionIDs.DELETE -> colors.buttonColorHangupDefault to Color.WHITE
            else -> colors.buttonColorSecondaryDefault to colors.textColorPrimary
        }
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = ColorDrawable(bg)
            isClickable = true
            contentDescription = item.title
            val icon = ImageView(context).apply {
                if (item.iconRes != 0) setImageResource(item.iconRes)
                setColorFilter(fg, PorterDuff.Mode.SRC_IN)
            }
            val size = (ConversationMenuSpec.SWIPE_ICON_DP * density).toInt()
            addView(icon, LinearLayout.LayoutParams(size, size))
            addView(
                TextView(context).apply {
                    text = item.title
                    setTextColor(fg)
                    setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, ConversationMenuSpec.SWIPE_TEXT_SP)
                    maxLines = 1
                    gravity = Gravity.CENTER
                    setPadding(0, (3 * density).toInt(), 0, 0)
                },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            )
            setOnClickListener {
                close()
                item.onClick()
            }
        }
    }

    private fun applyProgress(value: Float) {
        progress = value.coerceIn(0f, revealWidth.toFloat())
        front.translationX = direction * progress
        actionsContainer.visibility = if (progress > 0f) View.VISIBLE else View.INVISIBLE
    }

    private fun animateTo(target: Float) {
        animator?.cancel()
        animator = ValueAnimator.ofFloat(progress, target).apply {
            duration = 220L
            interpolator = DecelerateInterpolator()
            addUpdateListener { applyProgress(it.animatedValue as Float) }
            start()
        }
        if (target >= revealWidth && revealWidth > 0) onOpened?.invoke(this)
    }

    private fun isOverFront(x: Float): Boolean {
        val frontStart = if (direction < 0) 0f else progress
        val frontEnd = if (direction < 0) width - progress else width.toFloat()
        return x in frontStart..frontEnd
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (revealWidth == 0) return false
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = ev.x
                downY = ev.y
                startProgress = progress
                dragging = false
                tapToClose = false
                animator?.cancel()
                if (isOpen && isOverFront(ev.x)) {
                    tapToClose = true
                    return true
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging && detectHorizontalDrag(ev)) {
                    dragging = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
        }
        return false
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (revealWidth == 0) return false
        when (ev.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                if (!dragging && detectHorizontalDrag(ev)) {
                    dragging = true
                    tapToClose = false
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                if (dragging) {
                    val delta = (ev.x - downX) * direction
                    applyProgress(startProgress + delta)
                }
            }
            MotionEvent.ACTION_UP -> {
                if (dragging) {
                    animateTo(if (progress > revealWidth / 3f) revealWidth.toFloat() else 0f)
                } else if (tapToClose) {
                    close()
                }
                dragging = false
                tapToClose = false
            }
            MotionEvent.ACTION_CANCEL -> {
                if (dragging) animateTo(if (progress > revealWidth / 2f) revealWidth.toFloat() else 0f)
                dragging = false
                tapToClose = false
            }
        }
        return true
    }

    private fun detectHorizontalDrag(ev: MotionEvent): Boolean {
        val dx = ev.x - downX
        val dy = ev.y - downY
        if (abs(dx) <= touchSlop || abs(dx) <= abs(dy) * 1.2f) return false
        // Closed rows only react to a drag towards the start edge; open rows accept both directions.
        return progress > 0f || dx * direction > 0
    }
}
