package io.trtc.tuikit.chat.demo.chat

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.hostbase.HostImage

/** Full screen look at one card photo (a drawable name or an http url); it grows out of [source] and shrinks back into it. */
object DemoPhotoPreview {
    private const val DURATION_MS = 260L

    fun show(source: View, ref: String) {
        val activity = activityOf(source.context) ?: return
        if (activity.isFinishing || activity.isDestroyed) return
        val dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        val box = source.let { IntArray(2).also { xy -> it.getLocationOnScreen(xy) } }
        val sourceW = source.width.toFloat().coerceAtLeast(1f)
        val sourceH = source.height.toFloat().coerceAtLeast(1f)
        val sourceCx = box[0] + sourceW / 2f
        val sourceCy = box[1] + sourceH / 2f

        val root = FrameLayout(activity).apply { setBackgroundColor(Color.BLACK) }
        val image = ImageView(activity).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            HostImage.bind(this, ref)
        }
        root.addView(image, FrameLayout.LayoutParams(-1, -1))

        fun collapse(then: () -> Unit) {
            val fromScale = sourceW / root.width.coerceAtLeast(1)
            image.animate().cancel()
            root.animate().alpha(0f).setDuration(DURATION_MS).setInterpolator(DecelerateInterpolator()).start()
            image.animate()
                .scaleX(fromScale).scaleY(fromScale)
                .translationX(sourceCx - root.width / 2f).translationY(sourceCy - root.height / 2f)
                .setDuration(DURATION_MS).setInterpolator(DecelerateInterpolator())
                .withEndAction(then).start()
        }
        var closing = false
        fun close() {
            if (closing) return
            closing = true
            collapse { dialog.dismiss() }
        }
        root.setOnClickListener { close() }
        dialog.setOnKeyListener { _, keyCode, event ->
            if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                close()
                true
            } else keyCode == android.view.KeyEvent.KEYCODE_BACK
        }

        dialog.setContentView(root, ViewGroup.LayoutParams(-1, -1))
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setWindowAnimations(0)
            setLayout(-1, -1)
            addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
        }
        root.alpha = 0f
        root.post {
            val fromScale = sourceW / root.width.coerceAtLeast(1)
            image.scaleX = fromScale
            image.scaleY = fromScale
            image.translationX = sourceCx - root.width / 2f
            image.translationY = sourceCy - root.height / 2f
            root.animate().alpha(1f).setDuration(DURATION_MS).setInterpolator(DecelerateInterpolator()).start()
            image.animate().scaleX(1f).scaleY(1f).translationX(0f).translationY(0f)
                .setDuration(DURATION_MS).setInterpolator(DecelerateInterpolator()).start()
        }
        dialog.show()
    }

    private fun activityOf(context: Context): Activity? {
        var current: Context? = context
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return null
    }
}
