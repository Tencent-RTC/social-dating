package com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.hint

import android.animation.Animator
import android.animation.ObjectAnimator
import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewPropertyAnimator
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.tencent.qcloud.tuikit.tuicallkit.R
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkin
import io.trtc.tuikit.atomicxcore.api.call.CallMediaType
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.device.NetworkQuality
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

class HintView(context: Context) : AppCompatTextView(context) {
    private var stateJob: Job? = null
    private var transitionJob: Job? = null
    private var isFirstShowAccept = true
    private var callStatus = CallParticipantStatus.None

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        initView()
        registerObserver()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stateJob?.cancel()
        stateJob = null
        transitionJob?.cancel()
        transitionJob = null
    }

    private fun hostScope(): CoroutineScope? = findViewTreeLifecycleOwner()?.lifecycleScope

    fun playEndCallTransition(newText: String, holdDurationMs: Long, onComplete: () -> Unit = {}) {
        if (transitionJob?.isActive == true) {
            return
        }
        val parent = this.parent as? FrameLayout
        val scope = hostScope()
        if (parent == null || scope == null) {
            this.text = newText
            onComplete()
            return
        }

        stateJob?.cancel()
        stateJob = null

        val oldText = this.text?.toString().orEmpty()

        transitionJob = scope.launch {
            val density = resources.displayMetrics.density
            val measuredH = computeStableHeight(density)
            val childLp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                measuredH,
                Gravity.CENTER_HORIZONTAL or Gravity.TOP
            )
            val oldTv = createMirrorView(oldText).apply {
                translationY = 0f
                layoutParams = FrameLayout.LayoutParams(childLp)
            }
            val newTv = createMirrorView(newText).apply {
                translationY = measuredH.toFloat()
                layoutParams = FrameLayout.LayoutParams(childLp)
            }

            this@HintView.animate().cancel()
            this@HintView.translationY = 0f
            this@HintView.visibility = View.INVISIBLE
            parent.addView(oldTv)
            parent.addView(newTv)

            try {
                oldTv.animate()
                    .translationY(-measuredH.toFloat())
                    .setDuration(EXIT_DURATION_MS)
                    .setInterpolator(AccelerateInterpolator())
                newTv.animate()
                    .translationY(0f)
                    .setStartDelay(STAGGER_DELAY_MS)
                    .setDuration(ENTER_DURATION_MS)
                    .setInterpolator(DecelerateInterpolator())
                    .awaitEnd()

                ObjectAnimator.ofFloat(newTv, View.ALPHA, 1f, 1f).apply {
                    duration = 0L
                    startDelay = holdDurationMs
                }.awaitEnd()

                this@HintView.text = newText
                this@HintView.visibility = View.VISIBLE
            } finally {
                oldTv.animate().cancel()
                newTv.animate().cancel()
                (oldTv.parent as? ViewGroup)?.removeView(oldTv)
                (newTv.parent as? ViewGroup)?.removeView(newTv)
                this@HintView.visibility = View.VISIBLE
                onComplete()
            }
        }
    }

    private fun createMirrorView(content: String): AppCompatTextView {
        return AppCompatTextView(context).apply {
            this.text = content
            gravity = Gravity.CENTER
            setTextColor(this@HintView.currentTextColor)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, this@HintView.textSize)
            maxLines = 1
            includeFontPadding = false
        }
    }

    private fun computeStableHeight(density: Float): Int {
        val laidOut = this.height
        if (laidOut > 0) return laidOut
        val fm = paint.fontMetrics
        val lineH = fm.bottom - fm.top
        if (lineH > 0f) {
            return (lineH + density * 6f).toInt()
        }
        return (density * FALLBACK_HEIGHT_DP).toInt()
    }

    private fun registerObserver() {
        val scope = hostScope() ?: return
        stateJob = scope.launch {
            launch { observeCallStatus() }
            launch { observeNetworkQualities() }
        }
    }

    private suspend fun observeCallStatus() {
        CallStore.shared.observerState.selfInfo.collect { selfInfo ->
            if (callStatus != selfInfo.status) {
                callStatus = selfInfo.status
                updateStatusText()
            }
        }
    }

    private suspend fun observeNetworkQualities() {
        val selfId = CallStore.shared.observerState.selfInfo.value.id
        CallStore.shared.observerState.networkQualities.collect { networkQualities ->
            networkQualities.forEach { (userId, quality) ->
                if (isBadNetwork(quality)) {
                    text = if (userId == selfId) {
                        context.getString(R.string.callview_self_network_low_quality)
                    } else {
                        context.getString(R.string.callview_other_party_network_low_quality)
                    }
                    return@collect
                }
                updateStatusText()
            }
        }
    }

    private fun isBadNetwork(quality: NetworkQuality?): Boolean {
        return quality == NetworkQuality.BAD || quality == NetworkQuality.VERY_BAD
                || quality == NetworkQuality.DOWN
    }

    private fun initView() {
        setTextColor(CallSkin.tokens(context).textColorSecondary)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        gravity = Gravity.CENTER
        setTextSize(TypedValue.COMPLEX_UNIT_SP, HINT_TEXT_SIZE_SP)

        val activeCall = CallStore.shared.observerState.activeCall.value
        val isGroupCall = activeCall.inviteeIds.size >= 2
        text = if (isGroupCall) {
            if (selfIsCaller()) {
                context.getString(R.string.callview_wait_response)
            } else {
                context.getString(R.string.callview_wait_accept_group)
            }
        } else {
            updateStatusText()
        }
    }

    private fun updateSingleCallWaitingText(): String {
        val mediaType = CallStore.shared.observerState.activeCall.value.mediaType
        return if (selfIsCaller()) {
            context.getString(R.string.callview_waiting_accept)
        } else {
            if (CallMediaType.Video == mediaType) {
                context.getString(R.string.callview_invite_video_call)
            } else {
                context.getString(R.string.callview_invite_audio_call)
            }
        }
    }

    private fun updateStatusText(): String {
        val isGroupCall = CallStore.shared.observerState.activeCall.value.inviteeIds.size >= 2
        val self = CallStore.shared.observerState.selfInfo.value.copy()
        if (isGroupCall && CallParticipantStatus.Accept == self.status) {
            visibility = View.GONE
            return ""
        }

        if (self.status == CallParticipantStatus.Waiting) {
            return updateSingleCallWaitingText()
        }

        text = ""
        if (self.status == CallParticipantStatus.Accept && selfIsCaller() && isFirstShowAccept) {
            text = context.getString(R.string.callview_accept_single)
            postDelayed({
                isFirstShowAccept = false
                text = ""
            }, 2000)
        }
        return text.toString()
    }

    private fun selfIsCaller(): Boolean {
        val selfId = CallStore.shared.observerState.selfInfo.value.id
        val callerId = CallStore.shared.observerState.activeCall.value.inviterId
        return selfId == callerId
    }

    companion object {
        private const val EXIT_DURATION_MS = 150L
        private const val ENTER_DURATION_MS = 150L
        private const val STAGGER_DELAY_MS = 80L
        private const val FALLBACK_HEIGHT_DP = 28f
        private const val HINT_TEXT_SIZE_SP = 17f
    }
}

private suspend fun ViewPropertyAnimator.awaitEnd() = suspendCancellableCoroutine<Unit> { cont ->
    withEndAction {
        if (cont.isActive) cont.resumeWith(Result.success(Unit))
    }
    cont.invokeOnCancellation { cancel() }
}

private suspend fun Animator.awaitEnd() = suspendCancellableCoroutine<Unit> { cont ->
    doOnEnd {
        if (cont.isActive) cont.resumeWith(Result.success(Unit))
    }
    cont.invokeOnCancellation { cancel() }
    start()
}
