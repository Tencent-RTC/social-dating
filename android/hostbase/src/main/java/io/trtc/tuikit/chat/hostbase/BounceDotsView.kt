package io.trtc.tuikit.chat.hostbase

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.PI
import kotlin.math.sin

class BounceDotsView(context: Context, private val dotDp: Float = 4f, private val gapDp: Float = 3f, private val liftDp: Float = 4f) :
    View(context) {

    var dotColor: Int = DemoUi.tokens.textColorLink
        set(value) {
            field = value
            invalidate()
        }

    private val density = context.resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var phase = 0f
    private var animator: ValueAnimator? = null

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = ((dotDp * 3 + gapDp * 2) * density).toInt()
        val height = ((dotDp + liftDp) * density).toInt()
        setMeasuredDimension(width, height)
    }

    override fun onDraw(canvas: Canvas) {
        val diameter = dotDp * density
        val radius = diameter / 2
        for (index in 0 until DOTS) {
            val pulse = pulseAt(index)
            paint.color = dotColor
            paint.alpha = ((MIN_ALPHA + (1f - MIN_ALPHA) * pulse) * ALPHA_MAX).toInt()
            val cx = radius + index * (diameter + gapDp * density)
            val cy = height - radius - liftDp * density * pulse
            canvas.drawCircle(cx, cy, radius, paint)
        }
    }

    private fun pulseAt(index: Int): Float {
        if (animator == null) return if (index == 0) 1f else MIN_ALPHA
        var t = phase - index * STAGGER
        if (t < 0f) t += 1f
        return if (t < ACTIVE) sin(PI * t / ACTIVE).toFloat() else 0f
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startIfVisible()
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (visibility == VISIBLE) startIfVisible() else stop()
    }

    private fun startIfVisible() {
        if (animator != null || !isAttachedToWindow || visibility != VISIBLE) return
        if (!ValueAnimator.areAnimatorsEnabled()) {
            invalidate()
            return
        }
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = PERIOD_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                phase = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun stop() {
        animator?.cancel()
        animator = null
    }

    private companion object {
        const val DOTS = 3
        const val PERIOD_MS = 1200L
        const val STAGGER = 0.125f
        const val ACTIVE = 0.5f
        const val MIN_ALPHA = 0.4f
        const val ALPHA_MAX = 255
    }
}
