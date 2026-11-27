package com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.controls

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkinHub
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.RealCallSkinController
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.SocialCalleeWaitingView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.SocialCallControls
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.Logger
import io.trtc.tuikit.atomicxcore.api.call.CallMediaType
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Single-call bottom controls, skinned to design S9 / S10 (see `view/callview/skin`). The state machine
 * is unchanged: callee waiting -> accept / reject, caller waiting and accepted -> the control rows.
 */
class SingleCallControlsView(context: Context, private val hub: CallSkinHub) : FrameLayout(context) {
    private var subscribeStateJob: Job? = null
    private var functionLayout: View? = null
    private var callStatus = CallParticipantStatus.None

    var enableVirtualBackground: Boolean = true

    private var controlsHidden = false

    fun toggleControls() {
        if (functionLayout !is SocialCallControls) return
        controlsHidden = !controlsHidden
        animate().cancel()
        if (controlsHidden) {
            animate().alpha(0f).setDuration(180).withEndAction { if (controlsHidden) visibility = View.GONE }.start()
        } else {
            visibility = View.VISIBLE
            animate().alpha(1f).setDuration(180).start()
        }
    }

    private fun resetControlsVisibility() {
        controlsHidden = false
        animate().cancel()
        alpha = 1f
        visibility = View.VISIBLE
    }

    init {
        // The accept button pulses past its bounds; do not clip it here.
        clipChildren = false
        clipToPadding = false
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateLayout()
        registerSelfObserver()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        subscribeStateJob?.cancel()
    }

    private fun registerSelfObserver() {
        subscribeStateJob = CoroutineScope(Dispatchers.Main).launch {
            CallStore.shared.observerState.selfInfo.collect { selfInfo ->
                if (callStatus != selfInfo.status && selfInfo.status == CallParticipantStatus.Accept) {
                    callStatus = selfInfo.status
                    updateLayout()
                }
            }
        }
    }

    private fun updateLayout() {
        val mediaType = CallStore.shared.observerState.activeCall.value.mediaType
        val selfStatus = CallStore.shared.observerState.selfInfo.value.status

        val isVideo = mediaType == CallMediaType.Video
        when {
            selfStatus == CallParticipantStatus.Waiting && !selfIsCaller() ->
                functionLayout = SocialCalleeWaitingView(context, isVideo)

            selfStatus == CallParticipantStatus.Waiting || selfStatus == CallParticipantStatus.Accept ->
                functionLayout = SocialCallControls(
                    context,
                    RealCallSkinController(context, isVideo, enableVirtualBackground),
                    hub
                )
        }

        resetControlsVisibility()
        if (functionLayout == null) {
            Logger.e("functionLayout == null")
        } else {
            removeAllViews()
            addView(functionLayout, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        }
    }

    private fun selfIsCaller(): Boolean {
        val selfId = CallStore.shared.observerState.selfInfo.value.id
        val callerId = CallStore.shared.observerState.activeCall.value.inviterId
        return selfId == callerId
    }
}