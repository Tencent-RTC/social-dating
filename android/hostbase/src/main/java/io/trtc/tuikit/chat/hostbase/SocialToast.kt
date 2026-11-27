package io.trtc.tuikit.chat.hostbase

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.DrawableRes
import java.lang.ref.WeakReference

object SocialToast {
    enum class Kind { DEFAULT, SUCCESS, WARNING, ERROR }

    enum class Duration(val millis: Long) { SHORT(2000L), LONG(3200L) }

    private const val ENTER_MS = 260L
    private const val EXIT_MS = 180L
    private const val REPEAT_GUARD_MS = 600L
    private const val SIDE_GAP_DP = 12
    private const val MAX_WIDTH_DP = 420
    private const val CHIP_DP = 28
    private const val ICON_DP = 16
    private const val CHIP_TINT_ALPHA = 0.20f

    private val handler = Handler(Looper.getMainLooper())
    private var resumed: WeakReference<Activity>? = null
    private var shownView: View? = null
    private var shownHost: WeakReference<Activity>? = null
    private var dismissTask: Runnable? = null
    private var lastText = ""
    private var lastAt = 0L

    fun install(application: Application) {
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                resumed = WeakReference(activity)
            }

            override fun onActivityPaused(activity: Activity) {
                if (shownHost?.get() === activity) removeNow()
                if (resumed?.get() === activity) resumed = null
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) {
                if (shownHost?.get() === activity) removeNow()
            }
        })
    }

    fun hasHost(): Boolean = resumed?.get()?.let { !it.isFinishing && !it.isDestroyed } == true

    fun show(context: Context, text: String, kind: Kind = Kind.DEFAULT, duration: Duration = Duration.SHORT) {
        if (text.isBlank()) return
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { show(context, text, kind, duration) }
            return
        }
        val activity = activityOf(context) ?: resumed?.get()
        if (activity == null || activity.isFinishing || activity.isDestroyed) {
            Toast.makeText(context.applicationContext, text, Toast.LENGTH_SHORT).show()
            return
        }
        val now = System.currentTimeMillis()
        if (shownView != null && text == lastText && now - lastAt < REPEAT_GUARD_MS) return
        lastText = text
        lastAt = now
        removeNow()
        present(activity, text, kind, duration)
    }

    fun hide() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { hide() }
            return
        }
        dismissAnimated()
    }

    private fun activityOf(context: Context): Activity? {
        var current: Context? = context
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return null
    }

    private fun present(activity: Activity, text: String, kind: Kind, duration: Duration) {
        val host = activity.window.decorView as? ViewGroup ?: return
        val view = build(activity, text, kind)
        host.addView(view, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
        shownView = view
        shownHost = WeakReference(activity)
        val rise = DemoUi.dp(activity, 14).toFloat()
        view.alpha = 0f
        view.translationY = rise
        view.scaleX = 0.9f
        view.scaleY = 0.9f
        view.animate().alpha(1f).translationY(0f).scaleX(1f).scaleY(1f)
            .setDuration(ENTER_MS).setInterpolator(DecelerateInterpolator(1.6f)).start()
        view.announceForAccessibility(text)
        val task = Runnable { dismissAnimated() }
        dismissTask = task
        handler.postDelayed(task, duration.millis)
    }

    private fun build(activity: Activity, text: String, kind: Kind): View {
        val tokens = DemoUi.tokens
        val dark = DemoUi.isDark
        fun dp(value: Int) = DemoUi.dp(activity, value)
        val screenWidth = activity.resources.displayMetrics.widthPixels
        val maxWidth = minOf(screenWidth - dp(SIDE_GAP_DP) * 2, dp(MAX_WIDTH_DP))

        val accent = when (kind) {
            Kind.DEFAULT -> tokens.buttonColorPrimaryDefault
            Kind.SUCCESS -> tokens.textColorSuccess
            Kind.WARNING -> tokens.textColorWarning
            Kind.ERROR -> tokens.textColorError
        }
        @DrawableRes val iconRes = when (kind) {
            Kind.DEFAULT -> R.drawable.social_toast_heart
            Kind.SUCCESS -> R.drawable.social_toast_check
            Kind.WARNING -> R.drawable.social_toast_warning
            Kind.ERROR -> R.drawable.social_toast_error
        }

        val chip = FrameLayout(activity).apply {
            background = if (kind == Kind.DEFAULT) {
                GradientDrawable(
                    GradientDrawable.Orientation.TL_BR,
                    intArrayOf(tokens.buttonColorPrimaryDefault, tokens.tagColorLevel4)
                ).apply { shape = GradientDrawable.OVAL }
            } else {
                GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Host.alpha(accent, CHIP_TINT_ALPHA))
                }
            }
            addView(ImageView(activity).apply {
                setImageResource(iconRes)
                setColorFilter(if (kind == Kind.DEFAULT) tokens.textColorButton else accent)
            }, FrameLayout.LayoutParams(dp(ICON_DP), dp(ICON_DP), Gravity.CENTER))
        }

        val label = TextView(activity).apply {
            this.text = text
            textSize = 14f
            setTextColor(tokens.textColorPrimary)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setLineSpacing(0f, 1.08f)
            this.maxWidth = maxWidth - dp(8 + 10 + 18) - dp(CHIP_DP)
        }

        return LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(8), dp(18), dp(8))
            minimumHeight = dp(44)
            background = GradientDrawable().apply {
                cornerRadius = dp(28).toFloat()
                setColor(if (dark) tokens.bgColorOperate else tokens.bgColorDialog)
                setStroke(dp(1), tokens.strokeColorPrimary)
            }
            elevation = dp(10).toFloat()
            if (Build.VERSION.SDK_INT >= 28) outlineSpotShadowColor = tokens.shadowColor
            addView(chip, LinearLayout.LayoutParams(dp(CHIP_DP), dp(CHIP_DP)))
            addView(label, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(10) })
            contentDescription = text
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            attachGestures(this, dp(28))
        }
    }

    private fun attachGestures(view: View, dismissDistance: Int) {
        val slop = ViewConfiguration.get(view.context).scaledTouchSlop
        var downY = 0f
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    handler.removeCallbacks(dismissTask ?: return@setOnTouchListener true)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    target.translationY = minOf(0f, event.rawY - downY)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val dy = event.rawY - downY
                    if (dy < -dismissDistance || kotlin.math.abs(dy) < slop) {
                        dismissAnimated()
                    } else {
                        target.animate().translationY(0f).setDuration(ENTER_MS / 2).start()
                        dismissTask?.let { handler.postDelayed(it, Duration.SHORT.millis) }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    target.animate().translationY(0f).setDuration(ENTER_MS / 2).start()
                    true
                }
                else -> false
            }
        }
    }

    private fun dismissAnimated() {
        val view = shownView ?: return
        dismissTask?.let { handler.removeCallbacks(it) }
        dismissTask = null
        shownView = null
        val rise = DemoUi.dp(view.context, 8).toFloat()
        view.animate().alpha(0f).translationY(-rise).scaleX(0.96f).scaleY(0.96f).setDuration(EXIT_MS)
            .setInterpolator(AccelerateInterpolator()).withEndAction { detach(view) }.start()
    }

    private fun removeNow() {
        dismissTask?.let { handler.removeCallbacks(it) }
        dismissTask = null
        val view = shownView ?: return
        shownView = null
        view.animate().cancel()
        detach(view)
    }

    private fun detach(view: View) {
        (view.parent as? ViewGroup)?.removeView(view)
    }
}
