package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Space
import com.tencent.qcloud.tuikit.tuicallkit.R
import com.tencent.qcloud.tuikit.tuicallkit.manager.CallManager
import io.trtc.tuikit.atomicxcore.api.call.CallStore

/**
 * Incoming-call actions (design `ringScreen`): 拒绝 (hang-up red) and 接听 (accept green, pulsing),
 * 68dp buttons with a 10dp gap to the 12sp label. Behaviour is the original TUICallKit one:
 * reject -> `CallStore.reject`, accept -> `CallManager.accept`.
 */
class SocialCalleeWaitingView(
    context: Context,
    private val video: Boolean,
    private val onAccept: () -> Unit = { CallManager.instance.accept(null) },
    private val onReject: () -> Unit = { CallStore.shared.reject(null) }
) : LinearLayout(context) {
    private val t = CallSkin.tokens(context)
    private var pulse: ValueAnimator? = null
    private lateinit var acceptButton: FrameLayout
    private var acted = false

    init {
        orientation = HORIZONTAL
        gravity = Gravity.TOP
        clipChildren = false
        clipToPadding = false
        val side = CallSkin.dp(context, 52f)
        // Top room so the accept button's pulse (scale 1.08) is never clipped by an ancestor.
        setPadding(side, CallSkin.dp(context, 6f), side, CallSkin.dp(context, 24f))
        addView(column(R.drawable.callskin_ic_hangup, 30f, t.buttonColorHangupDefault, context.getString(R.string.callview_text_decline)) {
            if (acted) return@column
            acted = true
            getChildAt(2).alpha = 0.8f
            onReject()
        })
        addView(Space(context), LayoutParams(0, 1, 1f))
        addView(column(
            if (video) R.drawable.callskin_ic_accept_video else R.drawable.callskin_ic_accept_phone,
            28f, t.buttonColorAccept, context.getString(R.string.callview_text_dialing)
        ) {
            if (acted) return@column
            acted = true
            getChildAt(0).alpha = 0.8f
            onAccept()
        }.also { acceptButton = (it.getChildAt(0) as FrameLayout) })
    }

    private fun column(icon: Int, glyph: Float, color: Int, label: String, onClick: () -> Unit): LinearLayout {
        val col = LinearLayout(context).apply {
            orientation = VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            clipChildren = false
            layoutParams = LayoutParams(CallSkin.dp(context, 76f), -2)
        }
        val button = FrameLayout(context).apply {
            layoutParams = LayoutParams(CallSkin.dp(context, 68f), CallSkin.dp(context, 68f))
            background = CallSkin.oval(color)
            addView(CallSkin.icon(context, icon, glyph, Color.WHITE).apply {
                layoutParams = FrameLayout.LayoutParams(CallSkin.dp(context, glyph), CallSkin.dp(context, glyph), Gravity.CENTER)
            })
        }
        col.addView(button)
        col.addView(CallSkin.text(context, label, 12f, t.textColorPrimary), LayoutParams(-2, -2).apply { topMargin = CallSkin.dp(context, 10f) })
        CallSkin.pressable(col, 0.9f, onClick)
        return col
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        pulse = ValueAnimator.ofFloat(1f, 1.08f).apply {
            duration = 800
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener {
                val v = it.animatedValue as Float
                acceptButton.scaleX = v
                acceptButton.scaleY = v
            }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        pulse?.cancel()
        pulse = null
    }
}
