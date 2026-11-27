package io.trtc.tuikit.chat.hostbase

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Context
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.view.animation.Interpolator
import android.view.animation.PathInterpolator

object Motion {
    const val FAST = 140L
    const val BASE = 220L
    const val SLOW = 360L
    const val THEME = 420L

    val easeOut: Interpolator = PathInterpolator(0.22f, 0.61f, 0.36f, 1f)
    val easeInOut: Interpolator = PathInterpolator(0.45f, 0.05f, 0.55f, 0.95f)
    val spring: Interpolator = PathInterpolator(0.34f, 1.56f, 0.64f, 1f)

    fun enabled(context: Context): Boolean =
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) }
            .getOrDefault(1f) != 0f

    fun gridDelay(index: Int): Long = minOf(60L + index * 45L, 520L)

    fun rowDelay(index: Int): Long = minOf(index * 26L, 430L)

    fun fadeUp(view: View) {
        if (!enabled(view.context)) return
        val dy = Host.dpf(view.context, 10f)
        view.animate().cancel()
        view.alpha = 0f
        view.translationY = dy
        view.scaleX = 0.99f
        view.scaleY = 0.99f
        view.animate().alpha(1f).translationY(0f).scaleX(1f).scaleY(1f).setDuration(BASE).setInterpolator(easeOut).start()
    }

    fun rowIn(view: View, delay: Long, duration: Long = BASE) {
        if (!enabled(view.context)) return
        view.animate().cancel()
        view.alpha = 0f
        view.translationY = Host.dpf(view.context, 8f)
        view.animate().alpha(1f).translationY(0f).setStartDelay(delay).setDuration(duration).setInterpolator(easeOut).start()
    }

    fun staggerChildren(container: ViewGroup, grid: Boolean) {
        for (i in 0 until container.childCount) {
            val child = container.getChildAt(i)
            if (grid) rowIn(child, gridDelay(i), SLOW) else rowIn(child, rowDelay(i))
        }
    }

    fun cardLeave(view: View) {
        if (!enabled(view.context)) return
        view.animate().cancel()
        view.animate().alpha(0f).scaleX(0.94f).scaleY(0.94f).translationY(Host.dpf(view.context, 6f))
            .setDuration(200).setInterpolator(easeOut).start()
    }

    fun bump(view: View) {
        if (!enabled(view.context)) return
        view.animate().cancel()
        view.scaleX = 1f
        view.scaleY = 1f
        val up = AnimatorSet().apply {
            playTogether(ObjectAnimator.ofFloat(view, View.SCALE_X, 1f, 1.45f), ObjectAnimator.ofFloat(view, View.SCALE_Y, 1f, 1.45f))
            duration = (SLOW * 0.4f).toLong()
            interpolator = spring
        }
        val down = AnimatorSet().apply {
            playTogether(ObjectAnimator.ofFloat(view, View.SCALE_X, 1.45f, 1f), ObjectAnimator.ofFloat(view, View.SCALE_Y, 1.45f, 1f))
            duration = (SLOW * 0.6f).toLong()
            interpolator = spring
        }
        AnimatorSet().apply {
            playSequentially(up, down)
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationCancel(animation: Animator) {
                    view.scaleX = 1f
                    view.scaleY = 1f
                }
            })
            start()
        }
    }

    fun bubblePop(view: View, fromEnd: Boolean) {
        if (!enabled(view.context)) return
        view.animate().cancel()
        view.post {
            view.pivotX = if (fromEnd) view.width.toFloat() else 0f
            view.pivotY = view.height.toFloat()
            view.alpha = 0f
            view.scaleX = 0.72f
            view.scaleY = 0.72f
            view.translationY = Host.dpf(view.context, 10f)
            view.animate().alpha(1f).setDuration((SLOW * 0.6f).toLong()).setInterpolator(easeOut)
                .withEndAction { view.alpha = 1f }.start()
            ObjectAnimator.ofPropertyValuesHolder(
                view,
                android.animation.PropertyValuesHolder.ofFloat(View.SCALE_X, 0.72f, 1f),
                android.animation.PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.72f, 1f),
                android.animation.PropertyValuesHolder.ofFloat(View.TRANSLATION_Y, Host.dpf(view.context, 10f), 0f)
            ).apply {
                duration = SLOW
                interpolator = spring
                start()
            }
        }
    }

    fun kenBurns(view: View) {
        if (!enabled(view.context)) return
        view.animate().cancel()
        view.scaleX = 1f
        view.scaleY = 1f
        view.animate().scaleX(1.06f).scaleY(1.06f).setDuration(6000).setInterpolator(easeOut).start()
    }
}
