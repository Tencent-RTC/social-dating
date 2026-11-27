package io.trtc.tuikit.chat.home.ui

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import androidx.viewpager.widget.ViewPager
import io.trtc.tuikit.chat.hostbase.Motion
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.min

/** ViewPager that reports the start of every touch so an auto play slide can be handed over to the finger. */
class CoverViewPager(context: Context) : ViewPager(context) {
    var onTouchDown: (() -> Unit)? = null

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) onTouchDown?.invoke()
        return super.dispatchTouchEvent(ev)
    }
}

/**
 * Drives the profile cover: an endless loop (the adapter reports a huge page count and maps positions
 * with `% count`, so the slide always moves forward, also from the last photo back to the first),
 * a timed slide animated with a fake drag on our own easing curve, and the sliding indicator.
 * A touch cancels the running slide, a drag pauses the timer, and it resumes once the pager is idle.
 */
class CoverCarousel(
    private val pager: CoverViewPager,
    private val count: Int,
    private val indicator: CoverIndicator
) {
    companion object {
        const val LOOP_COUNT = Int.MAX_VALUE
        private const val INTERVAL_MS = 2500L
        private const val SLIDE_MS = 800L
        fun startPosition(count: Int): Int = (LOOP_COUNT / 2).let { it - it % count }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tick = Runnable { advance() }
    private var animator: ValueAnimator? = null
    private var running = false

    init {
        pager.onTouchDown = { cancelSlide() }
        pager.addOnPageChangeListener(object : ViewPager.SimpleOnPageChangeListener() {
            override fun onPageScrolled(position: Int, positionOffset: Float, positionOffsetPixels: Int) {
                indicator.progress = position % count + positionOffset
            }

            override fun onPageScrollStateChanged(state: Int) {
                when (state) {
                    ViewPager.SCROLL_STATE_DRAGGING -> if (animator == null) handler.removeCallbacks(tick)
                    ViewPager.SCROLL_STATE_IDLE -> schedule()
                }
            }
        })
    }

    fun start() {
        running = true
        schedule()
    }

    fun stop() {
        running = false
        handler.removeCallbacks(tick)
        cancelSlide()
    }

    private fun schedule() {
        handler.removeCallbacks(tick)
        if (running && count > 1) handler.postDelayed(tick, INTERVAL_MS)
    }

    private fun advance() {
        if (!running || count < 2 || animator != null || pager.isFakeDragging) return
        val width = pager.width - pager.paddingLeft - pager.paddingRight
        if (width <= 0 || !pager.beginFakeDrag()) {
            schedule()
            return
        }
        var last = 0f
        animator = ValueAnimator.ofFloat(0f, width.toFloat()).apply {
            duration = SLIDE_MS
            interpolator = Motion.easeInOut
            addUpdateListener {
                val value = it.animatedValue as Float
                if (pager.isFakeDragging) pager.fakeDragBy(-(value - last))
                last = value
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    finishSlide()
                    schedule()
                }
            })
            start()
        }
    }

    private fun cancelSlide() {
        handler.removeCallbacks(tick)
        animator?.let {
            it.removeAllListeners()
            it.cancel()
        }
        finishSlide()
    }

    private fun finishSlide() {
        animator = null
        if (pager.isFakeDragging) pager.endFakeDrag()
    }
}

/**
 * Cover page indicator. Every item is a 6dp dot that widens to a 14dp accent pill by the weight it
 * has at the pager's continuous (circular) position, and the neighbours are pushed aside so the gap
 * stays 5dp. Weights of the two items around the position always add up to one, so the total width is
 * constant and the pill morphs from one dot into the next, including the wrap from the last item back
 * to the first, instead of jumping.
 */
class CoverIndicator @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {
    var count = 0
        set(value) {
            field = value
            progress = 0f
            requestLayout()
            invalidate()
        }

    var progress = 0f
        set(value) {
            if (field == value) return
            field = value
            invalidate()
        }

    private val dot = Host.dpf(context, 6f)
    private val gap = Host.dpf(context, 5f)
    private val pillWidth = Host.dpf(context, 14f)
    private val idle = 0x66FFFFFF
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val n = count.coerceAtLeast(1)
        val width = n * dot + (n - 1) * gap + (pillWidth - dot)
        setMeasuredDimension(
            resolveSize(ceil(width).toInt(), widthMeasureSpec),
            resolveSize(ceil(dot).toInt(), heightMeasureSpec)
        )
    }

    override fun onDraw(canvas: Canvas) {
        if (count <= 0) return
        val accent = DemoUi.tokens.buttonColorPrimaryDefault
        var x = 0f
        for (index in 0 until count) {
            val weight = weight(index)
            val width = dot + (pillWidth - dot) * weight
            paint.color = blend(idle, accent, weight)
            rect.set(x, 0f, x + width, dot)
            canvas.drawRoundRect(rect, dot / 2, dot / 2, paint)
            x += width + gap
        }
    }

    private fun weight(index: Int): Float {
        var distance = abs(progress - index)
        distance = min(distance, count - distance)
        return (1f - distance).coerceIn(0f, 1f)
    }

    private fun blend(from: Int, to: Int, t: Float): Int {
        fun channel(shift: Int): Int {
            val a = (from ushr shift) and 0xFF
            val b = (to ushr shift) and 0xFF
            return (a + (b - a) * t).toInt().coerceIn(0, 255)
        }
        return (channel(24) shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
    }
}
