package io.trtc.tuikit.atomicx.albumpicker.util

import android.app.Activity
import android.graphics.Color
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.doOnLayout
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import java.lang.ref.WeakReference

internal object AlbumPickerWindowHelper {
    private const val TAG = "AlbumPickerWindow"
    private const val EDGE_TOLERANCE = 5
    private const val TAG_STATUS_BAR_FILL = "status_bar_fill"
    private const val TAG_NAV_BAR_FILL = "nav_bar_fill"

    private var touchesStatusBar = false
    private var touchesNavigationBar = false
    private var originalLightStatusBars: Boolean? = null
    private var originalLightNavigationBars: Boolean? = null

    @Suppress("DEPRECATION")
    private var originalStatusBarColor: Int? = null

    @Suppress("DEPRECATION")
    private var originalNavigationBarColor: Int? = null
    private var originalSoftInputMode: Int? = null
    private var isDetected = false
    private var savedEditTopPadding: Int? = null
    private var savedEditBottomPadding: Int? = null
    private var pickerViewRef: WeakReference<FrameLayout>? = null
    private var statusBarFillViewRef: WeakReference<View>? = null
    private var navigationBarFillViewRef: WeakReference<View>? = null

    fun setupEdgeToEdge(activity: Activity?, pickerView: View, onApplied: (() -> Unit)? = null) {
        pickerViewRef?.get()?.let {
            it.setPadding(it.paddingLeft, 0, it.paddingRight, 0)
            it.clipChildren = true
            it.clipToPadding = true
        }
        removeFillViews(pickerViewRef?.get())
        statusBarFillViewRef = null
        navigationBarFillViewRef = null
        pickerViewRef = null

        awaitStableInsetsThenApply(activity, pickerView, onApplied)
    }

    private fun removeFillViews(picker: FrameLayout?) {
        picker?.findViewWithTag<View>(TAG_STATUS_BAR_FILL)?.let { picker.removeView(it) }
        picker?.findViewWithTag<View>(TAG_NAV_BAR_FILL)?.let { picker.removeView(it) }
    }

    private fun awaitStableInsetsThenApply(
        activity: Activity?, pickerView: View, onApplied: (() -> Unit)?,
    ) {
        var applied = false
        val doApply = {
            if (!applied && isReadyToApply(pickerView)) {
                applied = true
                ViewCompat.setOnApplyWindowInsetsListener(pickerView, null)
                applyEdgeToEdge(activity, pickerView)
                onApplied?.invoke()
            }
        }
        ViewCompat.setOnApplyWindowInsetsListener(pickerView) { v, insets ->
            v.post { doApply() }
            insets
        }
        ViewCompat.requestApplyInsets(pickerView)
        pickerView.doOnLayout { it.post { doApply() } }
    }

    private fun isReadyToApply(view: View): Boolean =
        view.isLaidOut && view.height > 0 && view.rootView.height > 0 &&
            ViewCompat.getRootWindowInsets(view) != null

    private fun applyEdgeToEdge(activity: Activity?, pickerView: View) {
        val window = activity?.window ?: return
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val insets = ViewCompat.getRootWindowInsets(pickerView)
        val statusBarHeight = insets?.getInsets(WindowInsetsCompat.Type.statusBars())?.top ?: 0
        val navBarHeight = insets?.getInsets(WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0

        val layoutTop = getLayoutTopInWindow(pickerView)
        val layoutBottom = layoutTop + pickerView.height
        val windowHeight = pickerView.rootView.height

        touchesStatusBar = statusBarHeight > 0 && layoutTop <= statusBarHeight + EDGE_TOLERANCE
        touchesNavigationBar = navBarHeight > 0 && layoutBottom >= windowHeight - navBarHeight - EDGE_TOLERANCE

        Log.d(TAG, "applyEdgeToEdge: statusBarHeight=$statusBarHeight, navBarHeight=$navBarHeight, " +
            "layoutTop=$layoutTop, layoutBottom=$layoutBottom, windowHeight=$windowHeight, " +
            "pickerHeight=${pickerView.height}, touchesStatusBar=$touchesStatusBar, " +
            "touchesNavigationBar=$touchesNavigationBar")

        if (!touchesStatusBar && !touchesNavigationBar) {
            Log.w(TAG, "applyEdgeToEdge: early return, neither status nor nav bar touched, " +
                "no fill/padding applied")
            return
        }

        val controller = WindowCompat.getInsetsController(window, window.decorView)

        if (!isDetected) {
            isDetected = true
            originalLightStatusBars = controller.isAppearanceLightStatusBars
            originalLightNavigationBars = controller.isAppearanceLightNavigationBars
            @Suppress("DEPRECATION")
            if (touchesStatusBar) originalStatusBarColor = window.statusBarColor
            @Suppress("DEPRECATION")
            if (touchesNavigationBar) originalNavigationBarColor = window.navigationBarColor
        }

        val picker = pickerView as? FrameLayout
        if (picker == null) {
            Log.w(TAG, "applyEdgeToEdge: pickerView is not a FrameLayout " +
                "(${pickerView.javaClass.simpleName}), cannot add fill views / padding")
            return
        }
        removeFillViews(picker)

        var topPadding = 0
        var bottomPadding = 0
        var fillAdded = false
        if (touchesStatusBar) {
            topPadding = statusBarHeight
            val fillView =
                createFillView(picker, statusBarHeight, isTop = true, marginOffset = -statusBarHeight,
                    tag = TAG_STATUS_BAR_FILL)
            statusBarFillViewRef = WeakReference(fillView)
            picker.addView(fillView)
            fillAdded = true
        }
        if (touchesNavigationBar) {
            bottomPadding = navBarHeight
            val fillView =
                createFillView(picker, navBarHeight, isTop = false, marginOffset = -navBarHeight,
                    tag = TAG_NAV_BAR_FILL)
            navigationBarFillViewRef = WeakReference(fillView)
            picker.addView(fillView)
            fillAdded = true
        }
        if (fillAdded) {
            pickerViewRef = WeakReference(picker)
            picker.clipChildren = false
            picker.clipToPadding = false
            picker.setPadding(picker.paddingLeft, topPadding, picker.paddingRight, bottomPadding)
            Log.d(TAG, "applyEdgeToEdge: applied padding to picker top=$topPadding, bottom=$bottomPadding, " +
                "childCount=${picker.childCount}")
        }
    }

    @Suppress("DEPRECATION")
    fun applySystemBarColor(activity: Activity?, backgroundColor: Int) {
        if (!touchesStatusBar && !touchesNavigationBar) return

        val isLight = isColorLight(backgroundColor)
        val window = activity?.window
        if (window != null) {
            val controller = WindowCompat.getInsetsController(window, window.decorView)
            if (touchesStatusBar) {
                window.statusBarColor = Color.TRANSPARENT
                controller.isAppearanceLightStatusBars = isLight
            }
            if (touchesNavigationBar) {
                window.navigationBarColor = Color.TRANSPARENT
                controller.isAppearanceLightNavigationBars = isLight
            }
        }
        if (touchesStatusBar) {
            statusBarFillViewRef?.get()?.setBackgroundColor(backgroundColor)
        }
        if (touchesNavigationBar) {
            navigationBarFillViewRef?.get()?.setBackgroundColor(backgroundColor)
        }
    }

    fun setFillViewColor(color: Int) {
        statusBarFillViewRef?.get()?.setBackgroundColor(color)
        navigationBarFillViewRef?.get()?.setBackgroundColor(color)
    }

    fun enterEditImmersive() {
        val picker = pickerViewRef?.get()
        statusBarFillViewRef?.get()?.visibility = View.GONE
        navigationBarFillViewRef?.get()?.visibility = View.GONE
        picker?.let {
            if (savedEditTopPadding == null) {
                savedEditTopPadding = it.paddingTop
                savedEditBottomPadding = it.paddingBottom
            }
            it.setPadding(it.paddingLeft, 0, it.paddingRight, 0)
        }
    }

    fun exitEditImmersive(fillColor: Int) {
        val picker = pickerViewRef?.get()
        val restoreTop = savedEditTopPadding ?: picker?.paddingTop ?: 0
        val restoreBottom = savedEditBottomPadding ?: picker?.paddingBottom ?: 0
        picker?.setPadding(picker.paddingLeft, restoreTop, picker.paddingRight, restoreBottom)
        savedEditTopPadding = null
        savedEditBottomPadding = null
        statusBarFillViewRef?.get()?.let {
            it.setBackgroundColor(fillColor)
            it.visibility = View.VISIBLE
        }
        navigationBarFillViewRef?.get()?.let {
            it.setBackgroundColor(fillColor)
            it.visibility = View.VISIBLE
        }
    }

    @Suppress("DEPRECATION")
    fun restoreSystemBarColor(activity: Activity?, callerPickerView: View? = null) {
        val currentPicker = pickerViewRef?.get()
        if (callerPickerView != null && currentPicker != null &&
            callerPickerView !== currentPicker
        ) {
            return
        }

        val window = activity?.window
        if (window != null) {
            val controller = WindowCompat.getInsetsController(window, window.decorView)
            originalLightStatusBars?.let { controller.isAppearanceLightStatusBars = it }
            originalLightNavigationBars?.let { controller.isAppearanceLightNavigationBars = it }
            originalStatusBarColor?.let { window.statusBarColor = it }
            originalNavigationBarColor?.let { window.navigationBarColor = it }
        }

        pickerViewRef?.get()?.let {
            it.setPadding(it.paddingLeft, 0, it.paddingRight, 0)
            it.clipChildren = true
            it.clipToPadding = true
        }
        originalLightStatusBars = null
        originalLightNavigationBars = null
        originalStatusBarColor = null
        originalNavigationBarColor = null
        pickerViewRef = null
        statusBarFillViewRef = null
        navigationBarFillViewRef = null
        touchesStatusBar = false
        touchesNavigationBar = false
        isDetected = false
    }

    @Suppress("DEPRECATION")
    fun applySoftInputMode(
        activity: Activity?,
        containerView: View,
        vararg paddingTargets: View,
        onImeHidden: () -> Unit,
    ) {
        val window = activity?.window ?: return
        if (originalSoftInputMode == null) {
            originalSoftInputMode = window.attributes.softInputMode
        }
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN,
        )
        val callback = SoftInputAnimationCallback(containerView, paddingTargets, onImeHidden)
        ViewCompat.setWindowInsetsAnimationCallback(containerView, callback)
    }

    private class SoftInputAnimationCallback(
        private val containerView: View,
        private val paddingTargets: Array<out View>,
        private val onImeHidden: () -> Unit,
    ) : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_STOP) {

        override fun onProgress(
            insets: WindowInsetsCompat,
            runningAnimations: MutableList<WindowInsetsAnimationCompat>,
        ): WindowInsetsCompat {
            val imeHeight = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            val navBarHeight = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            val bottomPadding = (imeHeight - navBarHeight).coerceAtLeast(0)
            updateTargetsBottomPadding(bottomPadding)
            return insets
        }

        override fun onEnd(animation: WindowInsetsAnimationCompat) {
            val insets = ViewCompat.getRootWindowInsets(containerView) ?: return
            if (!insets.isVisible(WindowInsetsCompat.Type.ime())) {
                updateTargetsBottomPadding(0)
                onImeHidden()
            }
        }

        private fun updateTargetsBottomPadding(bottom: Int) {
            for (target in paddingTargets) {
                target.setPadding(target.paddingLeft, target.paddingTop, target.paddingRight, bottom)
            }
        }
    }

    fun restoreSoftInputMode(activity: Activity?, containerView: View, vararg paddingTargets: View) {
        val window = activity?.window ?: return
        originalSoftInputMode?.let { window.setSoftInputMode(it) }
        originalSoftInputMode = null
        ViewCompat.setWindowInsetsAnimationCallback(containerView, null)
        for (view in paddingTargets) {
            view.setPadding(view.paddingLeft, view.paddingTop, view.paddingRight, 0)
        }
    }

    private fun createFillView(parent: FrameLayout, height: Int, isTop: Boolean,
                               marginOffset: Int = 0, tag: String? = null): View =
        View(parent.context).apply {
            this.tag = tag
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, height
            ).apply {
                gravity = if (isTop) Gravity.TOP else Gravity.BOTTOM
                if (isTop) topMargin = marginOffset else bottomMargin = marginOffset
            }
            elevation = Float.MAX_VALUE
        }

    private fun getLayoutTopInWindow(view: View): Int {
        var top = view.top
        var current: android.view.ViewParent? = view.parent
        while (current is View) {
            top += current.top
            if (current === view.rootView) break
            current = (current as View).parent
        }
        return top
    }

    private fun isColorLight(color: Int): Boolean {
        val r = Color.red(color)
        val g = Color.green(color)
        val b = Color.blue(color)
        val luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luminance > 0.5
    }
}
