package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.LinearLayout

/**
 * A card that follows the finger and stays where it is dropped, kept inside its parent (below [minTop], e.g. the
 * status bar). It is laid out by its parent as usual; the drag only changes `translationX / Y`, so a taller card
 * (a longer topic) or a rotation re-clamps the position instead of losing it. Taps still reach the buttons inside:
 * only a move beyond the touch slop turns into a drag, which steals the gesture from the child.
 */
class DraggableCard(context: Context, private val minTop: Int) : LinearLayout(context) {
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private var downRawX = 0f
    private var downRawY = 0f
    private var startTx = 0f
    private var startTy = 0f
    private var dragging = false

    init {
        // A clickable card is "not blank space": a tap on it must not hide the call controls (see CallView).
        isClickable = true
    }

    private fun begin(ev: MotionEvent) {
        downRawX = ev.rawX
        downRawY = ev.rawY
        startTx = translationX
        startTy = translationY
        dragging = false
    }

    private fun exceedsSlop(ev: MotionEvent) =
        Math.abs(ev.rawX - downRawX) > slop || Math.abs(ev.rawY - downRawY) > slop

    private fun startDrag() {
        dragging = true
        parent?.requestDisallowInterceptTouchEvent(true)
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> begin(ev)
            MotionEvent.ACTION_MOVE -> if (!dragging && exceedsSlop(ev)) startDrag()
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging = false
        }
        return dragging
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> begin(ev)
            MotionEvent.ACTION_MOVE -> {
                if (!dragging && exceedsSlop(ev)) startDrag()
                if (dragging) {
                    translationX = startTx + (ev.rawX - downRawX)
                    translationY = startTy + (ev.rawY - downRawY)
                    clampToParent()
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging = false
        }
        return true
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        clampToParent()
    }

    private fun clampToParent() {
        val host = parent as? View ?: return
        if (host.width == 0 || width == 0) return
        val minX = -left.toFloat()
        val maxX = (host.width - width - left).toFloat().coerceAtLeast(minX)
        val minY = (minTop - top).toFloat()
        val maxY = (host.height - height - top).toFloat().coerceAtLeast(minY)
        translationX = translationX.coerceIn(minX, maxX)
        translationY = translationY.coerceIn(minY, maxY)
    }
}
