package com.tencent.qcloud.tuikit.tuicallkit.view.callview

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.view.ViewConfiguration
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import com.tencent.qcloud.tuikit.tuicallkit.R
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.CallViewFunction
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.CallUtils
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.ImageResourceCache
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.PeerAvatarMemory
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.Logger
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.controls.MultiCallControlsView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.controls.SingleCallControlsView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.hint.HintView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.hint.TimerView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.multi.MultiCallWaitingView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.transcriber.CallTranscriberView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkin
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkinHub
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallEffectsPanel
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallEffectsState
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkinLayer
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.TrtcCallEffectsEngine
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.VideoShadeView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.VoiceShadeView
import io.trtc.tuikit.atomicx.common.util.ScreenUtil.dip2px
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.smartcellularswitchrecommendation.SmartCellularRecommendationDialog
import io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast
import io.trtc.tuikit.atomicxcore.api.call.CallListener
import io.trtc.tuikit.atomicxcore.api.call.CallMediaType
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantInfo
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.device.DeviceStore
import io.trtc.tuikit.atomicxcore.api.device.NetworkQuality
import io.trtc.tuikit.atomicxcore.api.device.NetworkType
import io.trtc.tuikit.atomicxcore.api.view.CallCoreView
import io.trtc.tuikit.atomicxcore.api.view.CallLayoutTemplate
import io.trtc.tuikit.atomicxcore.api.view.CallViewAdapter
import io.trtc.tuikit.atomicxcore.api.view.VolumeLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

enum class Feature(val value: String) {
    AI_TRANSCRIBER("aiTranscriber"),
    VIRTUAL_BACKGROUND("virtualBackground"),
}

class CallView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : ConstraintLayout(context, attrs, defStyleAttr), CallViewFunction, CallViewAdapter {
    private data class ParticipantAvatarInfo(
        var originalUrl: String,
        var cachedPath: String?
    )
    private var callMainView: CallCoreView? = null
    private var transcriberContainer: FrameLayout? = null
    private var subscribeStateJob: Job? = null
    private val participantAvatarInfoMap: MutableMap<String, ParticipantAvatarInfo> = mutableMapOf()
    private val imageResourceCache = ImageResourceCache(context)

    private var layoutFunction: FrameLayout? = null
    private var layoutTimer: FrameLayout? = null
    private var layoutCallHint: FrameLayout? = null
    private var multiCallWaitingViewContainer: LinearLayout? = null
    private var disableFeatures: List<Feature>? = null
    private val skinHub = CallSkinHub(context)
    private val singleCallControlsView: SingleCallControlsView = SingleCallControlsView(context, skinHub)
    private var skinLayer: CallSkinLayer? = null

    private var callListener: CallListener = object : CallListener() {
        override fun onSuggestSwitchToCellular() {
            super.onSuggestSwitchToCellular()
            this@CallView.onSuggestSwitchToCellular()
        }
    }

    private var effectsPanel: CallEffectsPanel? = null

    init {
        initView()
        setIconResourcePath()
        skinHub.panelOpener = { kind -> showEffectsPanel(kind) }
    }

    /** Sound-effect / beauty sheet over the whole call page; opening the other kind replaces the current one. */
    private fun showEffectsPanel(kind: CallEffectsPanel.Kind) {
        hideEffectsPanel()
        val panel = CallEffectsPanel(context, kind, TrtcCallEffectsEngine(context)) { hideEffectsPanel() }
        effectsPanel = panel
        addView(panel, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        panel.alpha = 0f
        panel.animate().alpha(1f).setDuration(160).start()
    }

    private fun hideEffectsPanel() {
        effectsPanel?.let { panel ->
            effectsPanel = null
            panel.animate().alpha(0f).setDuration(120).withEndAction { removeView(panel) }.start()
        }
    }

    fun disableFeatures(features: List<Feature>?) {
        disableFeatures = features
        if (features?.contains(Feature.VIRTUAL_BACKGROUND) == true) {
            singleCallControlsView.enableVirtualBackground = false
        }
    }

    private var tapTracking = false
    private var tapOnClickable = false
    private var tapDownX = 0f
    private var tapDownY = 0f
    private val tapSlop = ViewConfiguration.get(context).scaledTouchSlop

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                tapTracking = true
                tapDownX = ev.rawX
                tapDownY = ev.rawY
                tapOnClickable = hitsClickable(this, ev.rawX.toInt(), ev.rawY.toInt())
            }
            MotionEvent.ACTION_MOVE -> {
                if (Math.abs(ev.rawX - tapDownX) > tapSlop || Math.abs(ev.rawY - tapDownY) > tapSlop) tapTracking = false
            }
            MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_CANCEL -> tapTracking = false
            MotionEvent.ACTION_UP -> {
                if (tapTracking && !tapOnClickable && ev.eventTime - ev.downTime < 450 && isVideoCall()) {
                    singleCallControlsView.toggleControls()
                }
                tapTracking = false
            }
        }
        val handled = super.dispatchTouchEvent(ev)
        return if (ev.actionMasked == MotionEvent.ACTION_DOWN && !handled && !tapOnClickable) true else handled
    }

    /**
     * True when a touch at (rawX, rawY) would be taken by a clickable view. Mirrors how Android dispatches a touch:
     * siblings are tried from the top one down, a view that does not take the touch lets it fall through to the
     * ones below. This matters because the skin layer is a full-screen transparent overlay stacked above the
     * controls: following only the topmost view at the point would stop at that overlay and report every button as
     * "blank space", so tapping a button also hid the controls.
     */
    private fun hitsClickable(root: View, rawX: Int, rawY: Int): Boolean {
        val loc = IntArray(2)
        fun takesTouch(view: View): Boolean {
            if (view.visibility != View.VISIBLE) return false
            view.getLocationOnScreen(loc)
            if (rawX < loc[0] || rawX >= loc[0] + view.width || rawY < loc[1] || rawY >= loc[1] + view.height) return false
            if (view is ViewGroup) {
                for (i in view.childCount - 1 downTo 0) {
                    if (takesTouch(view.getChildAt(i))) return true
                }
            }
            return view !== root && (view.isClickable || view.hasOnClickListeners())
        }
        return takesTouch(root)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        addFunctionLayout()
        addTranscriberLayout()
        updateWaitingView()
        // The sound effects and the beauty levels are user preferences: the call opens with the saved ones.
        CallEffectsState.load(context)
        runCatching { CallEffectsState.applyTo(TrtcCallEffectsEngine(context)) }
        CallStore.shared.addListener(callListener)
        subscribeStateJob = CoroutineScope(Dispatchers.Main).launch {
            supervisorScope {
                launch { observeSelfInfo() }
                launch { observeParticipantInfo() }
                launch { observeNetworkType() }
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        effectsPanel = null
        skinHub.panelOpener = null
        callMainView?.removeAllViews()
        callListener.let { CallStore.shared.removeListener(it) }
        subscribeStateJob?.cancel()
    }

    private suspend fun observeSelfInfo() {
        CallStore.shared.observerState.selfInfo.collect { selfInfo ->
            val isAccepted = selfInfo.status == CallParticipantStatus.Accept
            if (isAccepted && callMainView?.visibility == GONE) {
                updateWaitingView()
            }
        }
    }

    private suspend fun observeParticipantInfo() {
        CallStore.shared.observerState.allParticipants.collect { allParticipants ->
            updateParticipantsAvatars(allParticipants)
            updatePeerName(allParticipants)
        }
    }

    /** Header name of the skinned single-call page: the other participant's remark, nickname or id. */
    private fun updatePeerName(participants: Collection<CallParticipantInfo>) {
        val selfId = CallStore.shared.observerState.selfInfo.value.id
        val peer = participants.firstOrNull { it.id != selfId } ?: return
        skinLayer?.setPeerName(peer.remark.ifEmpty { peer.name }.ifEmpty { peer.id })
    }

    private suspend fun observeNetworkType() {
        DeviceStore.shared().deviceState.networkType.collect { networkType ->
            handleNetworkTypeChanged(networkType)
        }
    }

    private fun initView() {
        LayoutInflater.from(context).inflate(R.layout.callview_root_view, this, true)
        multiCallWaitingViewContainer = findViewById(R.id.ll_callee_waiting_view)
        layoutFunction = findViewById(R.id.rl_layout_function)
        layoutTimer = findViewById(R.id.rl_layout_call_time)
        layoutCallHint = findViewById(R.id.rl_layout_call_hint)
        callMainView = CallCoreView(context)
        val layoutParams = ConstraintLayout.LayoutParams(ConstraintLayout.LayoutParams.MATCH_PARENT, ConstraintLayout.LayoutParams.MATCH_PARENT)
        this.addView(callMainView, 0, layoutParams)
        callMainView?.callViewAdapter = this
    }

    private fun updateWaitingView() {
        val selfUser = CallStore.shared.observerState.selfInfo.value
        if (CallParticipantStatus.Waiting == selfUser.status && !CallUtils.isCaller(selfUser.id) && isMultiCall()) {
            multiCallWaitingViewContainer?.addView(MultiCallWaitingView(context))
            multiCallWaitingViewContainer?.visibility = VISIBLE
            callMainView?.visibility = GONE
            layoutCallHint?.visibility = GONE
            layoutTimer?.visibility = GONE
        } else {
            multiCallWaitingViewContainer?.visibility = GONE
            callMainView?.visibility = VISIBLE
            layoutCallHint?.visibility = VISIBLE
            layoutTimer?.visibility = VISIBLE
        }
    }

    private fun setIconResourcePath() {
        CallCoreView.defaultAvatarImage = avatarPlaceholder()

        val volumeLevelIcons = mapOf(
            VolumeLevel.Mute to imageResourceCache.getDrawablePath(R.drawable.callview_ic_self_mute),
            VolumeLevel.Low to imageResourceCache.getDrawablePath(R.drawable.callview_ic_audio_input),
            VolumeLevel.Medium to imageResourceCache.getDrawablePath(R.drawable.callview_ic_audio_input),
            VolumeLevel.High to imageResourceCache.getDrawablePath(R.drawable.callview_ic_audio_input),
            VolumeLevel.Peak to imageResourceCache.getDrawablePath(R.drawable.callview_ic_audio_input),
        )
        callMainView?.setVolumeLevelIcons(volumeLevelIcons)

        val networkQualityIcons = mapOf(
            NetworkQuality.BAD to imageResourceCache.getDrawablePath(R.drawable.callview_ic_network_bad),
            NetworkQuality.VERY_BAD to imageResourceCache.getDrawablePath(R.drawable.callview_ic_network_bad)
        )
        callMainView?.setNetworkQualityIcons(networkQualityIcons)
        callMainView?.setWaitingAnimation(imageResourceCache.getDrawablePath(R.drawable.callview_ic_loading))
    }

    private fun avatarPlaceholder(): Drawable? {
        if (isMultiCall()) return ContextCompat.getDrawable(context, R.drawable.callview_ic_avatar)
        val state = CallStore.shared.observerState
        val selfId = state.selfInfo.value.id
        val url = state.allParticipants.value.firstOrNull { it.id != selfId }?.avatarURL.orEmpty()
        return PeerAvatarMemory.drawable(context, url) ?: ColorDrawable(Color.TRANSPARENT)
    }

    private fun addTranscriberLayout() {
        if (disableFeatures?.contains(Feature.AI_TRANSCRIBER) == true) {
            return
        }
        transcriberContainer = findViewById<FrameLayout>(R.id.call_layout_transcriber_container)
        transcriberContainer?.addView(CallTranscriberView(context))
    }

    private fun addFunctionLayout() {
        if (isMultiCall()) {
            addMultiFunctionLayout()
        } else {
            addSingleFunctionLayout()
        }
    }

    private fun addMultiFunctionLayout() {
        val enableVirtualBackground = disableFeatures?.contains(Feature.VIRTUAL_BACKGROUND) != true
        val controlsView = MultiCallControlsView(context)
        controlsView.enableVirtualBackground = enableVirtualBackground
        layoutFunction?.addView(controlsView)
        layoutTimer?.addView(TimerView(context))
        layoutCallHint?.addView(HintView(context))
    }

    private fun addSingleFunctionLayout() {
        singleCallControlsView.enableVirtualBackground =
            disableFeatures?.contains(Feature.VIRTUAL_BACKGROUND) != true
        val isVideo = CallStore.shared.observerState.activeCall.value.mediaType == io.trtc.tuikit.atomicxcore.api.call.CallMediaType.Video
        val placeholderHeightDp = if (isVideo) SINGLE_VIDEO_CONTROLS_HEIGHT_DP else SINGLE_AUDIO_CONTROLS_HEIGHT_DP
        layoutFunction?.layoutParams = layoutFunction?.layoutParams?.apply {
            height = dip2px(placeholderHeightDp)
        }
        applySingleCallSkin(isVideo)
        layoutTimer?.addView(TimerView(context))
        layoutCallHint?.addView(HintView(context))
    }

    /**
     * Design S9 / S10: scrim (voice: under the SDK avatar; video: over the remote picture), a header
     * overlay with the peer name, and the time / hint line moved under the name.
     */
    private fun applySingleCallSkin(isVideo: Boolean) {
        if (skinLayer != null) return
        val tokens = CallSkin.tokens(context)
        val topInset = getStatusBarHeight()
        // Video: the shade lives inside the SDK overlay *under* the controls (see onCreateOverlayView); a shade
        // above the SDK view would also dim the control buttons, which sit in that same overlay.
        if (!isVideo) {
            addView(VoiceShadeView(context, tokens), 0, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }
        val layer = CallSkinLayer(context, skinHub, isVideo, topInset)
        addView(layer, if (isVideo) 2 else 2, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        skinLayer = layer
        updatePeerName(CallStore.shared.observerState.allParticipants.value)
        val lineTop = topInset + dip2px(28f)
        (layoutTimer?.layoutParams as? LayoutParams)?.let { it.topMargin = lineTop; layoutTimer?.layoutParams = it }
        (layoutCallHint?.layoutParams as? LayoutParams)?.let {
            // The hint ("对方网络不佳" ...) sits right under the timer line instead of on top of it. While no timer
            // is shown (waiting) the timer frame is empty, so the hint takes the timer's place.
            it.topToTop = LayoutParams.UNSET
            it.topToBottom = R.id.rl_layout_call_time
            it.topMargin = dip2px(4f)
            layoutCallHint?.layoutParams = it
        }
    }

    override fun onCreateOverlayView(layout: CallLayoutTemplate): View? {
        if (layout != CallLayoutTemplate.Float) return null
        (singleCallControlsView.parent as? ViewGroup)?.removeView(singleCallControlsView)
        val isVideo = CallStore.shared.observerState.activeCall.value.mediaType == io.trtc.tuikit.atomicxcore.api.call.CallMediaType.Video
        return FrameLayout(context).apply {
            if (isVideo && !isMultiCall()) {
                addView(VideoShadeView(context), FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                ))
            }
            addView(singleCallControlsView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = android.view.Gravity.BOTTOM })
        }
    }

    private fun updateParticipantsAvatars(participants: Collection<CallParticipantInfo>) {
        val participantsToUpdate = mutableListOf<Pair<String, String>>()
        val currentParticipantIds = participants.map { it.id }.toSet()
        val removedIds = participantAvatarInfoMap.keys.filter { it !in currentParticipantIds }
        val hasRemovedParticipants = removedIds.isNotEmpty()
        removedIds.forEach { id ->
            participantAvatarInfoMap.remove(id)
        }
        for (participant in participants) {
            val participantId = participant.id
            val currentAvatarUrl = participant.avatarURL ?: ""
            val existingInfo = participantAvatarInfoMap[participantId]
            if (existingInfo?.originalUrl != currentAvatarUrl) {
                participantsToUpdate.add(participantId to currentAvatarUrl)
                participantAvatarInfoMap[participantId] = ParticipantAvatarInfo(
                    originalUrl = currentAvatarUrl,
                    cachedPath = existingInfo?.cachedPath
                )
            }
        }
        
        if (participantsToUpdate.isEmpty()) {
            if (hasRemovedParticipants) {
                val avatarMap = buildAvatarPathMap()
                callMainView?.setParticipantAvatars(avatarMap)
            }
            return
        }
        
        val completedCount = AtomicInteger(0)
        val totalCount = participantsToUpdate.size
        
        for ((participantId, avatarUrl) in participantsToUpdate) {
            imageResourceCache.cacheNetworkImage(avatarUrl) { cachedPath ->
                synchronized(participantAvatarInfoMap) {
                    val info = participantAvatarInfoMap[participantId]
                    if (info != null) {
                        if (cachedPath != null) {
                            info.cachedPath = File(cachedPath).absolutePath
                            if (isSinglePeer(participantId)) {
                                PeerAvatarMemory.remember(context, avatarUrl, info.cachedPath!!)?.let {
                                    CallCoreView.defaultAvatarImage = it
                                }
                            }
                        } else {
                            if (isSinglePeer(participantId) && peerProfileLoaded(participantId)) {
                                CallCoreView.defaultAvatarImage = ContextCompat.getDrawable(context, R.drawable.callview_ic_avatar)
                            }
                            val defaultAvatarPath = imageResourceCache.getDefaultAvatarPath(R.drawable.callview_ic_avatar)
                            info.cachedPath = defaultAvatarPath
                            if (defaultAvatarPath == null) {
                                participantAvatarInfoMap.remove(participantId)
                            }
                        }
                    }
                    if (completedCount.incrementAndGet() == totalCount) {
                        val avatarMap = buildAvatarPathMap()
                        callMainView?.setParticipantAvatars(avatarMap)
                    }
                }
            }
        }
    }

    private fun isSinglePeer(participantId: String): Boolean =
        !isMultiCall() && participantId != CallStore.shared.observerState.selfInfo.value.id

    private fun peerProfileLoaded(participantId: String): Boolean =
        CallStore.shared.observerState.allParticipants.value.firstOrNull { it.id == participantId }?.name?.isNotEmpty() == true

    private fun buildAvatarPathMap(): Map<String, String> {
        return participantAvatarInfoMap
            .filter { it.value.cachedPath != null }
            .mapValues { it.value.cachedPath!! }
    }

    private fun onSuggestSwitchToCellular() {
        this.post {
            try {
                val dialog = SmartCellularRecommendationDialog(context)
                dialog.onEnableSmartCellular = {
                    enableCellularFallback()
                }
                dialog.show()
            } catch (e: Exception) {
                Logger.e("showSmartCellularRecommendation failed: ${e.message}")
            }
        }
    }

    private fun handleNetworkTypeChanged(type: NetworkType) {
        val toastString = when (type) {
            NetworkType.CELLULAR -> context.getString(R.string.smart_cellular_switched_to_cellular)
            NetworkType.WIFI -> context.getString(R.string.smart_cellular_switched_to_wifi)
            else -> return
        }
        AtomicToast.show(context, toastString)
    }


    override fun setLayoutTemplate(template: CallLayoutTemplate) {
        val isPipView = template == CallLayoutTemplate.Pip
        layoutFunction?.visibility = if (isPipView) GONE else VISIBLE
        layoutCallHint?.visibility = if (isPipView) GONE else VISIBLE
        layoutTimer?.visibility = if (isPipView) GONE else VISIBLE
        multiCallWaitingViewContainer?.visibility = if (isPipView) GONE else VISIBLE
        callMainView?.visibility = VISIBLE
        updateCallCoreViewTopMargin(template)
        callMainView?.setLayoutTemplate(template)
        transcriberContainer?.isVisible = !isPipView
    }

    private fun updateCallCoreViewTopMargin(template: CallLayoutTemplate) {
        val marginTop = if (template == CallLayoutTemplate.Grid) {
            getStatusBarHeight() + dip2px(GRID_VIDEO_CONTAINER_MARGIN_TOP_DP)
        } else {
            0
        }
        val layoutParams = callMainView?.layoutParams as? ConstraintLayout.LayoutParams
        layoutParams?.let {
            it.topMargin = marginTop
            callMainView?.layoutParams = it
        }
    }

    private fun getStatusBarHeight(): Int {
        var statusBarHeight = 0
        val resourceId = this.resources.getIdentifier(STATUS_BAR_HEIGHT, DIMEN, ANDROID)
        if (resourceId > 0) {
            statusBarHeight = this.resources.getDimensionPixelSize(resourceId)
        }
        return statusBarHeight
    }

    private fun isVideoCall(): Boolean =
        CallStore.shared.observerState.activeCall.value.mediaType == CallMediaType.Video

    private fun isMultiCall(): Boolean {
        val inviteeIdListSize = CallStore.shared.observerState.activeCall.value.inviteeIds.size
        val chatGroupId = CallStore.shared.observerState.activeCall.value.chatGroupId
        return chatGroupId.isNotEmpty() || inviteeIdListSize > 1
    }

    private fun enableCellularFallback() {
        val json = JSONObject()
        json.put("api", "enableCellularFallback")
        json.put("params", JSONObject().put("enable", true))
        CallStore.shared.callExperimentalAPI(json.toString())
    }

    companion object {
        private const val GRID_VIDEO_CONTAINER_MARGIN_TOP_DP = 45f
        private const val SINGLE_AUDIO_CONTROLS_HEIGHT_DP = 330f
        private const val SINGLE_VIDEO_CONTROLS_HEIGHT_DP = 250f
        private const val STATUS_BAR_HEIGHT = "status_bar_height"
        private const val DIMEN = "dimen"
        private const val ANDROID = "android"
    }
}