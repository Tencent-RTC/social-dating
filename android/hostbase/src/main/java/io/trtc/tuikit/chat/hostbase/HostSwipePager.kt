package io.trtc.tuikit.chat.hostbase

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

/**
 * Page container for second-level tabs (推荐 / 附近 / 新人, 消息 / 好友 / 通话).
 *
 * - Every page is built the first time it is shown ([provider]) and kept afterwards: switching only hides / shows it,
 *   so nothing is rebuilt or refetched and each page keeps its scroll position.
 * - A tab tap ([show] with `animate`) slides the old page out and the new one in, from the side the tab lies on.
 * - A horizontal drag follows the finger and settles on the neighbour page (or springs back).
 * - [onProgress] reports the continuous position (`1.5` = half way from page 1 to page 2) on every frame of a slide, a
 *   drag and a settle, so the tab bar above can travel with the pages.
 */
class HostSwipePager(context: Context) : FrameLayout(context) {
    /** Builds the page of an index. Called at most once per index until [invalidate] / [reset]. */
    var provider: (Int) -> View = { View(context) }

    /** Number of pages. */
    var pageCount = 0

    /** Fired when a drag decides to move to another page, before the settle animation ends (the tab bar follows). */
    var onSwiped: (Int) -> Unit = {}

    /** Continuous page position, called on every frame of a slide / drag / settle and once for a plain jump. */
    var onProgress: (Float) -> Unit = {}

    var swipeEnabled = true

    /**
     * Lets a child keep its own horizontal gesture: called with the touch-down point (pager coordinates) and the drag
     * direction (-1 = towards the next page); return true to leave the drag to the child.
     */
    var yieldDrag: (x: Float, y: Float, direction: Int) -> Boolean = { _, _, _ -> false }

    var index = -1
        private set

    private val pages = HashMap<Int, View>()
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private val minFling = ViewConfiguration.get(context).scaledMinimumFlingVelocity.coerceAtLeast(Host.dp(context, 400))
    private var settle: Animator? = null

    private var downX = 0f
    private var downY = 0f
    private var dragging = false
    private var absorbing = false
    private var dragTarget = -1
    private var dragFrom = 0
    private var dragOffset = 0f
    private var velocity: VelocityTracker? = null

    fun pageAt(position: Int): View? = pages[position]

    /** Forgets (and removes) a page; the next [show] of that index builds it again. */
    fun invalidate(position: Int) {
        finishSettle()
        pages.remove(position)?.let { removeView(it) }
        if (position == index) index = -1
    }

    fun reset() {
        finishSettle()
        pages.clear()
        removeAllViews()
        index = -1
    }

    private fun ensure(position: Int): View = pages.getOrPut(position) {
        provider(position).also { addView(it, LayoutParams(-1, -1)) }
    }

    /** Shows page [position]; with [animate] it slides in from the side of the tab that was tapped. */
    fun show(position: Int, animate: Boolean) {
        if (position !in 0 until pageCount) return
        finishSettle()
        val old = pages[index]
        val from = index
        val next = ensure(position)
        index = position
        if (next === old) {
            next.visibility = VISIBLE
            onProgress(position.toFloat())
            return
        }
        val canAnimate = animate && old != null && from >= 0 && width > 0 && Motion.enabled(context)
        if (!canAnimate) {
            pages.values.forEach { it.visibility = if (it === next) VISIBLE else GONE; it.translationX = 0f }
            onProgress(position.toFloat())
            return
        }
        val direction = if (position > from) 1 else -1
        pages.values.forEach { if (it !== old && it !== next) it.visibility = GONE }
        next.visibility = VISIBLE
        next.translationX = direction * width.toFloat()
        slide(old!!, next, direction, 0f, SLIDE_MS, from, position)
    }

    /** [progress] 0..1 is how far the pair has already travelled. */
    private fun slide(old: View, next: View, direction: Int, progress: Float, duration: Long, fromPage: Int, toPage: Int) {
        val w = width.toFloat()
        settle = ValueAnimator.ofFloat(progress, 1f).apply {
            this.duration = duration
            interpolator = Motion.easeOut
            addUpdateListener {
                val t = it.animatedValue as Float
                old.translationX = -direction * w * t
                next.translationX = direction * w * (1f - t)
                onProgress(fromPage + (toPage - fromPage) * t)
            }
            addListener(object : AnimatorListenerAdapter() {
                private var cancelled = false
                override fun onAnimationCancel(animation: Animator) { cancelled = true }
                override fun onAnimationEnd(animation: Animator) {
                    old.visibility = GONE
                    old.translationX = 0f
                    next.translationX = 0f
                    if (settle === animation) settle = null
                }
            })
            start()
        }
    }

    /** Jumps a running settle animation to its end so the next change starts from a clean state. */
    private fun finishSettle() {
        settle?.let { it.end() }
        settle = null
    }

    // ------------------------------------------------------------------ drag

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (!swipeEnabled || pageCount < 2 || index < 0) return false
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                finishSettle()
                downX = ev.x
                downY = ev.y
                dragging = false
                absorbing = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (dragging || absorbing) return true
                val dx = ev.x - downX
                val dy = ev.y - downY
                if (abs(dx) > slop && abs(dx) > abs(dy) * 1.5f) {
                    val direction = if (dx < 0) 1 else -1
                    val target = index + direction
                    if (yieldDrag(downX, downY, -direction)) return false
                    if (target !in 0 until pageCount) {
                        // First / last page dragged outwards: nothing to move to, but the gesture must not fall through to
                        // the page, or the full-width row under the finger still sees its UP inside its bounds and clicks.
                        // Taking the gesture cancels the child's press; the pager then just swallows it.
                        absorbing = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                        return true
                    }
                    beginDrag(target)
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
        }
        return false
    }

    private fun beginDrag(target: Int) {
        dragging = true
        dragTarget = target
        dragFrom = index
        dragOffset = 0f
        val next = ensure(target)
        pages.values.forEach { if (it !== next && it !== pages[index]) it.visibility = GONE }
        next.visibility = VISIBLE
        next.translationX = if (target > index) width.toFloat() else -width.toFloat()
        velocity?.recycle()
        velocity = VelocityTracker.obtain()
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (absorbing) {
            if (ev.actionMasked == MotionEvent.ACTION_UP || ev.actionMasked == MotionEvent.ACTION_CANCEL) absorbing = false
            return true
        }
        if (!dragging) return false
        velocity?.addMovement(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                val raw = ev.x - downX
                // Towards the next page the offset is negative, towards the previous one positive; never past the origin.
                dragOffset = if (dragTarget > index) raw.coerceIn(-width.toFloat(), 0f) else raw.coerceIn(0f, width.toFloat())
                applyDrag()
                reportDrag()
            }
            MotionEvent.ACTION_UP -> release(cancelled = false)
            MotionEvent.ACTION_CANCEL -> release(cancelled = true)
        }
        return true
    }

    private fun applyDrag() {
        val current = pages[index] ?: return
        val next = pages[dragTarget] ?: return
        current.translationX = dragOffset
        next.translationX = dragOffset + if (dragTarget > index) width else -width
    }

    /** Position implied by the current drag offset, relative to the page the drag started on. */
    private fun reportDrag() {
        if (width == 0) return
        onProgress(dragFrom + (dragTarget - dragFrom) * (abs(dragOffset) / width))
    }

    private fun release(cancelled: Boolean) {
        val tracker = velocity
        tracker?.computeCurrentVelocity(1000)
        val vx = tracker?.xVelocity ?: 0f
        tracker?.recycle()
        velocity = null
        dragging = false
        val current = pages[index]
        val next = pages[dragTarget]
        if (current == null || next == null || width == 0) return
        val towardsNext = dragTarget > index
        val travelled = abs(dragOffset) / width
        val flingForward = if (towardsNext) vx < -minFling else vx > minFling
        val flingBack = if (towardsNext) vx > minFling else vx < -minFling
        val commit = !cancelled && !flingBack && (travelled > 0.35f || flingForward)
        val w = width.toFloat()
        val startOffset = dragOffset
        val targetOffset = if (commit) (if (towardsNext) -w else w) else 0f
        val target = dragTarget
        val previous = index
        if (commit) {
            index = target
            onSwiped(target)
        }
        val distance = abs(targetOffset - startOffset)
        settle = ValueAnimator.ofFloat(startOffset, targetOffset).apply {
            duration = (Motion.BASE * (distance / w).coerceIn(0.35f, 1f)).toLong().coerceAtLeast(90L)
            interpolator = Motion.easeOut
            addUpdateListener {
                dragOffset = it.animatedValue as Float
                current.translationX = dragOffset
                next.translationX = dragOffset + if (towardsNext) w else -w
                reportDrag()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    val gone = if (commit) current else next
                    gone.visibility = GONE
                    current.translationX = 0f
                    next.translationX = 0f
                    if (settle === animation) settle = null
                }
            })
            start()
        }
        if (!commit) index = previous
    }

    private companion object {
        /** A tap slides a little longer than the generic base motion: the tab bar travels the same distance. */
        val SLIDE_MS = Motion.BASE + 100
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        finishSettle()
    }
}
