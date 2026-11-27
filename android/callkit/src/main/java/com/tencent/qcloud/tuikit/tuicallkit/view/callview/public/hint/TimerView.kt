package com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.hint

import android.content.Context
import androidx.appcompat.widget.AppCompatTextView
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import androidx.core.content.ContextCompat
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkin
import com.tencent.qcloud.tuicore.util.DateTimeUtil
import com.tencent.qcloud.tuikit.tuicallkit.R
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class TimerView(context: Context) : AppCompatTextView(context) {
    private var subscribeStateJob: Job? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        initView()
        registerActiveCallObserver()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        subscribeStateJob?.cancel()
    }

    private fun registerActiveCallObserver() {
        subscribeStateJob = CoroutineScope(Dispatchers.Main).launch {
            CallStore.shared.observerState.activeCall.collect { activeCall ->
                updateDurationView(activeCall.duration)
            }
        }
    }

    private fun initView() {
        // Design S9 / S10 `.calltop__time`: 12sp secondary text with a 6dp success dot, tabular digits.
        val tokens = CallSkin.tokens(context)
        setTextColor(tokens.textColorSecondary)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        val dot = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(tokens.textColorSuccess)
            val size = CallSkin.dp(context, 6f)
            setSize(size, size)
        }
        setCompoundDrawablesRelativeWithIntrinsicBounds(dot, null, null, null)
        compoundDrawablePadding = CallSkin.dp(context, 4f)
        fontFeatureSettings = "tnum"
        val duration = CallStore.shared.observerState.activeCall.value.duration
        updateDurationView(duration)
    }

    private fun updateDurationView(time: Long) {
        val self = CallStore.shared.observerState.selfInfo.value
        if (self.status == CallParticipantStatus.Accept) {
            text = DateTimeUtil.formatSecondsTo00(time.toInt())
            visibility = VISIBLE
        } else {
            visibility = GONE
        }
    }
}