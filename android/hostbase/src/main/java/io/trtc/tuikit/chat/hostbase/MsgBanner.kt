package io.trtc.tuikit.chat.hostbase

import android.app.Activity
import android.app.Application
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
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.lang.ref.WeakReference

object MsgBanner {
    data class Model(val key: String, val title: String, val summary: CharSequence, val time: String, val avatar: String?)

    private var summaryView: TextView? = null
    private var summaryKey: String? = null

    /** Called when the emoji pictures of [key]'s summary are loaded; ignored if the banner has moved on. */
    fun updateSummary(key: String, summary: CharSequence) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { updateSummary(key, summary) }
            return
        }
        if (summaryKey == key) summaryView?.text = summary
    }

    private const val ENTER_MS = 360L
    private const val SWAP_MS = 280L
    private const val EXIT_MS = 240L
    private const val AUTO_HIDE_MS = 3500L
    private const val SIDE_DP = 8
    private const val TOP_DP = 8
    private const val AVATAR_DP = 40
    private const val MAX_WIDTH_DP = 560

    private val handler = Handler(Looper.getMainLooper())
    private var resumed: WeakReference<Activity>? = null
    private var shownView: View? = null
    private var shownHost: WeakReference<Activity>? = null
    private var hideTask: Runnable? = null

    val isForeground: Boolean get() = resumed?.get() != null

    val currentActivity: Activity? get() = resumed?.get()

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

    fun show(model: Model, onClick: () -> Unit): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { show(model, onClick) }
            return true
        }
        val activity = resumed?.get()?.takeIf { !it.isFinishing && !it.isDestroyed } ?: return false
        val host = activity.window.decorView as? ViewGroup ?: return false
        val swap = shownView != null && shownHost?.get() === activity
        if (!swap) removeNow() else detachCurrent()
        val view = build(activity, model, onClick)
        summaryKey = model.key
        host.addView(view, FrameLayout.LayoutParams(-1, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            val bars = ViewCompat.getRootWindowInsets(host)?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            topMargin = (bars?.top ?: 0) + DemoUi.dp(activity, TOP_DP)
            marginStart = DemoUi.dp(activity, SIDE_DP) + (bars?.left ?: 0)
            marginEnd = DemoUi.dp(activity, SIDE_DP) + (bars?.right ?: 0)
        })
        shownView = view
        shownHost = WeakReference(activity)
        if (swap) {
            view.scaleX = 0.97f
            view.scaleY = 0.97f
            view.animate().scaleX(1f).scaleY(1f).setDuration(SWAP_MS).setInterpolator(OvershootInterpolator(2.2f)).start()
        } else {
            view.alpha = 0f
            view.translationY = -DemoUi.dp(activity, 120).toFloat()
            view.animate().alpha(1f).translationY(0f).setDuration(ENTER_MS).setInterpolator(OvershootInterpolator(1.1f)).start()
        }
        view.announceForAccessibility("${model.title}, ${model.summary}")
        scheduleHide()
        return true
    }

    fun hide() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { hide() }
            return
        }
        dismissAnimated()
    }

    private fun build(activity: Activity, model: Model, onClick: () -> Unit): View {
        val tokens = DemoUi.tokens
        val dark = DemoUi.isDark
        fun dp(value: Int) = DemoUi.dp(activity, value)
        val avatar = AvatarView(activity, model.title, sizeDp = AVATAR_DP).apply { load(model.avatar) }
        val name = TextView(activity).apply {
            text = model.title
            textSize = 14f
            setTextColor(tokens.textColorPrimary)
            setTypeface(typeface, Typeface.BOLD)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            includeFontPadding = false
        }
        val time = TextView(activity).apply {
            text = model.time
            textSize = 11f
            setTextColor(tokens.textColorTertiary)
            maxLines = 1
            includeFontPadding = false
        }
        val summary = TextView(activity).apply {
            summaryView = this
            text = model.summary
            textSize = 13f
            setTextColor(tokens.textColorSecondary)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            includeFontPadding = false
        }
        val top = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(name, LinearLayout.LayoutParams(0, -2, 1f))
            addView(time, LinearLayout.LayoutParams(-2, -2).apply { marginStart = dp(8) })
        }
        val texts = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(top, LinearLayout.LayoutParams(-1, -2))
            addView(summary, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
        }
        return LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(Host.alpha(if (dark) tokens.bgColorOperate else tokens.bgColorDialog, 1f))
                setStroke(dp(1), tokens.strokeColorPrimary)
            }
            elevation = dp(12).toFloat()
            if (Build.VERSION.SDK_INT >= 28) outlineSpotShadowColor = tokens.shadowColor
            addView(avatar)
            addView(texts, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(10) })
            contentDescription = "${model.title}, ${model.summary}"
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            isClickable = true
            attachGestures(this, dp(24), onClick)
        }
    }

    private fun attachGestures(view: View, dismissDistance: Int, onClick: () -> Unit) {
        val slop = ViewConfiguration.get(view.context).scaledTouchSlop
        var downY = 0f
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    hideTask?.let { handler.removeCallbacks(it) }
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    target.translationY = minOf(0f, event.rawY - downY)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val dy = event.rawY - downY
                    when {
                        dy < -dismissDistance -> dismissAnimated()
                        kotlin.math.abs(dy) < slop -> {
                            removeNow()
                            onClick()
                        }
                        else -> {
                            target.animate().translationY(0f).setDuration(ENTER_MS / 2).start()
                            scheduleHide()
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    target.animate().translationY(0f).setDuration(ENTER_MS / 2).start()
                    scheduleHide()
                    true
                }
                else -> false
            }
        }
    }

    private fun scheduleHide() {
        hideTask?.let { handler.removeCallbacks(it) }
        val task = Runnable { dismissAnimated() }
        hideTask = task
        handler.postDelayed(task, AUTO_HIDE_MS)
    }

    private fun dismissAnimated() {
        val view = shownView ?: return
        hideTask?.let { handler.removeCallbacks(it) }
        hideTask = null
        shownView = null
        view.animate().cancel()
        view.animate().alpha(0f).translationY(-DemoUi.dp(view.context, 120).toFloat()).setDuration(EXIT_MS)
            .setInterpolator(AccelerateInterpolator()).withEndAction { detach(view) }.start()
    }

    private fun detachCurrent() {
        hideTask?.let { handler.removeCallbacks(it) }
        hideTask = null
        val view = shownView ?: return
        shownView = null
        view.animate().cancel()
        detach(view)
    }

    private fun removeNow() = detachCurrent()

    private fun detach(view: View) {
        (view.parent as? ViewGroup)?.removeView(view)
    }
}
