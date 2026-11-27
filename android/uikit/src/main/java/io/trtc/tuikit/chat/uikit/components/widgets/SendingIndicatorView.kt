package io.trtc.tuikit.chat.uikit.components.widgets

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.ProgressBar
import androidx.core.content.ContextCompat
import io.trtc.tuikit.chat.uikit.R

internal class SendingIndicatorView(context: Context) : ProgressBar(context) {

    private var rotator: ObjectAnimator? = null
    private var spinning = false

    init {
        isIndeterminate = true
        indeterminateDrawable = ContextCompat.getDrawable(context, R.drawable.message_list_sending_indicator)
    }

    fun start() {
        spinning = true
        if (isAttachedToWindow) {
            startRotator()
        }
    }

    fun stop() {
        spinning = false
        cancelRotator()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (spinning) {
            startRotator()
        }
    }

    override fun onDetachedFromWindow() {
        cancelRotator()
        super.onDetachedFromWindow()
    }

    private fun startRotator() {
        if (rotator?.isRunning == true) {
            return
        }
        rotator = ObjectAnimator.ofFloat(this, View.ROTATION, 0f, 360f).apply {
            duration = ROTATION_DURATION_MS
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            interpolator = LinearInterpolator()
            start()
        }
    }

    private fun cancelRotator() {
        rotator?.cancel()
        rotator = null
        rotation = 0f
    }

    private companion object {
        const val ROTATION_DURATION_MS = 800L
    }
}
