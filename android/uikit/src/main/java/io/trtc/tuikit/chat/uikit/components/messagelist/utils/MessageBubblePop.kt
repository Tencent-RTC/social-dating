package io.trtc.tuikit.chat.uikit.components.messagelist.utils

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.provider.Settings
import android.view.View
import android.view.animation.PathInterpolator

object MessageBubblePop {
    private const val DURATION_MS = 360L
    private val spring = PathInterpolator(0.34f, 1.56f, 0.64f, 1f)
    private val easeOut = PathInterpolator(0.22f, 0.61f, 0.36f, 1f)

    fun enabled(view: View): Boolean =
        runCatching { Settings.Global.getFloat(view.context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) }
            .getOrDefault(1f) != 0f

    private val running = java.util.WeakHashMap<View, android.animation.Animator>()

    fun reset(view: View) {
        running.remove(view)?.cancel()
        view.animate().cancel()
        if (view.alpha != 1f || view.scaleX != 1f || view.scaleY != 1f || view.translationY != 0f) {
            view.alpha = 1f
            view.scaleX = 1f
            view.scaleY = 1f
            view.translationY = 0f
        }
    }

    fun play(view: View, fromEnd: Boolean) {
        if (!enabled(view)) return
        reset(view)
        val rise = 10f * view.resources.displayMetrics.density
        view.post {
            view.pivotX = if (fromEnd) view.width.toFloat() else 0f
            view.pivotY = view.height.toFloat()
            view.alpha = 0f
            view.animate().alpha(1f).setDuration((DURATION_MS * 0.6f).toLong()).setInterpolator(easeOut)
                .withEndAction { view.alpha = 1f }.start()
            ObjectAnimator.ofPropertyValuesHolder(
                view,
                PropertyValuesHolder.ofFloat(View.SCALE_X, 0.72f, 1f),
                PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.72f, 1f),
                PropertyValuesHolder.ofFloat(View.TRANSLATION_Y, rise, 0f)
            ).apply {
                duration = DURATION_MS
                interpolator = spring
                running[view] = this
                start()
            }
        }
    }
}
