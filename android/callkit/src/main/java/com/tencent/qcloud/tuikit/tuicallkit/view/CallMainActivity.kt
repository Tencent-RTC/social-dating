package com.tencent.qcloud.tuikit.tuicallkit.view

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.text.TextUtils
import android.util.Log
import android.util.Rational
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.activity.enableEdgeToEdge
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import com.tencent.qcloud.tuicore.TUICore
import com.tencent.qcloud.tuicore.interfaces.ITUINotification
import com.tencent.qcloud.tuicore.util.TUIBuild
import com.tencent.qcloud.tuikit.tuicallkit.R
import com.tencent.qcloud.tuikit.tuicallkit.beauty.BeautyIntegration
import com.tencent.qcloud.tuikit.tuicallkit.common.data.Constants
import com.tencent.qcloud.tuikit.tuicallkit.common.data.Logger
import com.tencent.qcloud.tuikit.tuicallkit.common.metrics.KeyMetrics
import com.tencent.qcloud.tuikit.tuicallkit.common.utils.DeviceUtils
import com.tencent.qcloud.tuikit.tuicallkit.manager.CallManager
import com.tencent.qcloud.tuikit.tuicallkit.state.GlobalState
import com.tencent.qcloud.tuikit.tuicallkit.state.ViewState
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.CallView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.Feature
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.public.hint.HintView
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin.CallSkin
import android.content.res.ColorStateList
import com.tencent.qcloud.tuikit.tuicallkit.view.component.inviteuser.InviteUserButton
import com.trtc.tuikit.common.FullScreenActivity
import com.trtc.tuikit.common.imageloader.ImageLoader
import com.trtc.tuikit.common.imageloader.ImageOptions
import com.trtc.tuikit.common.ui.floatwindow.FloatWindowManager
import io.trtc.tuikit.atomicx.common.permission.PermissionRequester
import io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast
import io.trtc.tuikit.atomicxcore.api.call.CallEndReason
import io.trtc.tuikit.atomicxcore.api.call.CallListener
import io.trtc.tuikit.atomicxcore.api.call.CallMediaType
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.view.CallLayoutTemplate
import kotlinx.coroutines.flow.first

class CallMainActivity : FullScreenActivity(), ITUINotification {
    private var callView: CallView? = null
    private var imageFloatIcon: ImageView? = null
    private var imageBeautyIcon: ImageView? = null
    private var beautyIconVisibility = View.GONE
    private var inviteUserButton: FrameLayout? = null
    private var callViewContainer: FrameLayout? = null
    private var isShowingEndHint: Boolean = false
    private val callStatusObserver = object : CallListener() {
        override fun onCallEnded(callId: String, mediaType: CallMediaType, reason: CallEndReason, userId: String) {
            runOnUiThread {
                handleCallEnded(reason, userId)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        DeviceUtils.setScreenLockParams(window)
        if (TUIBuild.getVersionInt() >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        setContentView(R.layout.tuicallkit_activity_call_kit)
        applyWindowInsets()
        requestedOrientation = when (GlobalState.instance.orientation) {
            Constants.Orientation.Portrait -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            Constants.Orientation.LandScape -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        callViewContainer = findViewById(R.id.call_view_container)
        CallStore.shared.addListener(callStatusObserver)
        lifecycleScope.launchWhenStarted {
            CallStore.shared.observerState.selfInfo.first {
                if (it.status == CallParticipantStatus.Accept) {
                    Log.i(TAG, "CallStore.shared.observerState.selfInfo accept")
                    val groupId = CallStore.shared.observerState.activeCall.value.chatGroupId
                    val inviteeSize = CallStore.shared.observerState.activeCall.value.inviteeIds.size
                    val mediaType = CallStore.shared.observerState.activeCall.value.mediaType
                    if (mediaType == CallMediaType.Video && groupId.isEmpty() && inviteeSize == 1) {
                        addBeautyView()
                    }
                    true
                }
                false
            }
        }
        TUICore.registerEvent(KEY_EXTENSION_NAME, NOTIFY_START_ACTIVITY, this)
        CallManager.instance.startForegroundService()
    }

    private fun applyWindowInsets() {
        val rootView = findViewById<View>(R.id.root_container)
        ViewCompat.setOnApplyWindowInsetsListener(rootView) { view, windowInsets ->
            val insets = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(bottom = insets.bottom)
            // Design S9 / S10: the 36dp pip button sits in the 48dp header row below the status bar.
            (imageFloatIcon?.layoutParams as? androidx.constraintlayout.widget.ConstraintLayout.LayoutParams)?.let {
                it.topMargin = insets.top + CallSkin.dp(this, 6f)
                imageFloatIcon?.layoutParams = it
            }
            windowInsets
        }
    }

    private fun initView() {
        if (isShowingEndHint) {
            return
        }
        val callStatus = CallStore.shared.observerState.selfInfo.value.status
        if (CallParticipantStatus.None == callStatus) {
            Logger.i(TAG, "initView, selfStatus is None, finish directly")
            finishCallMainActivity()
            return
        }
        val callId = CallStore.shared.observerState.activeCall.value.callId
        KeyMetrics.countUV(KeyMetrics.EventId.WAKEUP, callId)
        setBackground()
        addCallView()
        addFloatButton()
        addInviteButton()
        FloatWindowManager.sharedInstance().dismiss()
        CallManager.instance.viewState.router.set(ViewState.ViewRouter.FullView)
        handleCallAcceptAction()
    }

    private fun finishCallMainActivity() {
        isShowingEndHint = false
        if (isFinishing || isDestroyed) {
            return
        }
        if (TUIBuild.getVersionInt() >= Build.VERSION_CODES.LOLLIPOP && isTaskRoot) {
            finishAndRemoveTask()
        } else {
            finish()
        }
    }

    private fun addCallView() {
        if (callViewContainer == null) {
            callViewContainer = findViewById(R.id.call_view_container)
        }
        callViewContainer?.removeAllViews()
        callView?.removeAllViews()
        callView = CallView(this)
        val chatGroupId = CallStore.shared.observerState.activeCall.value.chatGroupId
        val inviteeIdListSize = CallStore.shared.observerState.activeCall.value.inviteeIds.size
        if (inviteeIdListSize == 1 && chatGroupId.isEmpty()) {
            callView?.setLayoutTemplate(CallLayoutTemplate.Float)
        } else {
            callView?.setLayoutTemplate(CallLayoutTemplate.Grid)
        }
        val featuresToDisable = mutableListOf<Feature>()
        if (!GlobalState.instance.enableAITranscriber) {
            featuresToDisable.add(Feature.AI_TRANSCRIBER)
        }
        if (!GlobalState.instance.enableVirtualBackground) {
            featuresToDisable.add(Feature.VIRTUAL_BACKGROUND)
        }
        if (featuresToDisable.isNotEmpty()) {
            callView?.disableFeatures(featuresToDisable)
        }
        val view = GlobalState.instance.callAdapter?.onCreateMainView(callView!!) ?: callView
        callViewContainer?.addView(view)
    }

    private fun addBeautyView() {
        imageBeautyIcon = findViewById(R.id.iv_beauty)
        beautyIconVisibility =
            if (BeautyIntegration.isSupportTEBeauty() && !isInPipModeSafe()) View.VISIBLE else View.GONE
        imageBeautyIcon?.visibility = beautyIconVisibility
        imageBeautyIcon?.setOnClickListener {
            BeautyIntegration.showBeautyDialog(this)
        }
    }

    private fun addFloatButton() {
        imageFloatIcon = findViewById(R.id.image_float_icon)
        imageFloatIcon?.let { icon ->
            val tokens = CallSkin.tokens(this)
            val size = CallSkin.dp(this, 36f)
            icon.layoutParams = icon.layoutParams.apply { width = size; height = size }
            icon.setPadding(CallSkin.dp(this, 8f), CallSkin.dp(this, 8f), CallSkin.dp(this, 8f), CallSkin.dp(this, 8f))
            icon.background = CallSkin.offOval(this)
            icon.setImageResource(R.drawable.callskin_ic_pip)
            icon.imageTintList = ColorStateList.valueOf(android.graphics.Color.WHITE)
            val top = ViewCompat.getRootWindowInsets(icon)?.getInsets(WindowInsetsCompat.Type.systemBars())?.top ?: 0
            (icon.layoutParams as? androidx.constraintlayout.widget.ConstraintLayout.LayoutParams)?.let {
                it.topMargin = top + CallSkin.dp(this, 6f)
                it.marginStart = CallSkin.dp(this, 16f)
                icon.layoutParams = it
            }
        }
        imageFloatIcon?.setOnClickListener {
            if (FloatWindowManager.sharedInstance().isPictureInPictureSupported) {
                enterPictureInPictureModeWithBuild()
            }
        }
    }

    private fun addInviteButton() {
        inviteUserButton = findViewById(R.id.rl_layout_invite_user)
        if (shouldShowInviteButton()) {
            inviteUserButton?.visibility = View.VISIBLE
            inviteUserButton?.addView(InviteUserButton(this))
            return
        }
        inviteUserButton?.visibility = View.GONE
    }

    private fun shouldShowInviteButton(): Boolean {
        val chatGroupId = CallStore.shared.observerState.activeCall.value.chatGroupId
        return !chatGroupId.isNullOrEmpty()
    }

    private fun setBackground() {
        val imageBackground = findViewById<ImageView>(R.id.img_view_background)
        // Design S9: the blurred background is the *other* party's avatar (TUICallKit used the own avatar).
        val state = CallStore.shared.observerState
        val selfId = state.selfInfo.value.id
        val peer = state.allParticipants.value.firstOrNull { it.id != selfId } ?: state.selfInfo.value
        val builder = ImageOptions.Builder().setBlurEffect(80f)
        if (peer.avatarURL.isNullOrEmpty()) builder.setPlaceImage(R.drawable.tuicallkit_ic_avatar)
        val option = builder.build()
        ImageLoader.load(this, imageBackground, peer.avatarURL, option)
        imageBackground?.setColorFilter(ContextCompat.getColor(this, R.color.callkit_color_blur_mask))
    }

    private fun handleCallAcceptAction() {
        val selfStatus = CallStore.shared.observerState.selfInfo.value.status
        if (selfStatus == CallParticipantStatus.Accept) {
            return
        }
        if (intent.action == Constants.ACCEPT_CALL_ACTION) {
            Logger.i(TAG, "IncomingView -> handleCallAcceptAction")
            CallManager.instance.accept(null)
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent != null) {
            setIntent(intent)
        }
    }

    override fun onResume() {
        super.onResume()
        initView()
    }

    override fun onDestroy() {
        super.onDestroy()
        TUICore.unRegisterEvent(this)
        CallStore.shared.removeListener(callStatusObserver)
        CallManager.instance.stopForegroundService()
        BeautyIntegration.resetBeauty()
    }

    override fun onUserLeaveHint() {
        val hasAudioPermission = PermissionRequester.newInstance(Manifest.permission.RECORD_AUDIO).has()
        if (!hasAudioPermission) {
            return
        }
        val hasVideoPermission = PermissionRequester.newInstance(Manifest.permission.CAMERA).has()
        val mediaType = CallStore.shared.observerState.activeCall.value.mediaType
        if (mediaType == CallMediaType.Video && !hasVideoPermission) {
            return
        }
        enterPictureInPictureModeWithBuild()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        imageFloatIcon?.visibility = if (isInPictureInPictureMode) View.GONE else View.VISIBLE
        imageBeautyIcon?.visibility = if (isInPictureInPictureMode) View.GONE else beautyIconVisibility
        if (shouldShowInviteButton()) {
            inviteUserButton?.visibility = if (isInPictureInPictureMode) View.GONE else View.VISIBLE
        }
        if (isInPictureInPictureMode) {
            callView?.setLayoutTemplate(CallLayoutTemplate.Pip)
        } else {
            hangupOnPipWindowClose()
        }
    }

    private fun hangupOnPipWindowClose() {
        if (lifecycle.currentState != Lifecycle.State.CREATED) {
            return
        }
        val callerId = CallStore.shared.observerState.activeCall.value.inviterId
        val selfId = CallStore.shared.observerState.selfInfo.value.id
        val selfStatus = CallStore.shared.observerState.selfInfo.value.status
        Logger.i(TAG, "user close pip window , callerId = $callerId , selfId = $selfId , selfStatus=$selfStatus")
        if (selfId == callerId) {
            CallManager.instance.hangup(null)
            return
        }
        if (selfStatus == CallParticipantStatus.Waiting) {
            CallManager.instance.reject(null)
        } else {
            CallManager.instance.hangup(null)
        }
    }

    private fun enterPictureInPictureModeWithBuild() {
        if (!lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            return
        }
        if (TUIBuild.getVersionInt() >= Build.VERSION_CODES.O && hasPipModePermission()) {
            val pictureInPictureParams: PictureInPictureParams.Builder = PictureInPictureParams.Builder()
            val floatViewWidth = resources.getDimensionPixelSize(R.dimen.callkit_video_small_view_width)
            val floatViewHeight = resources.getDimensionPixelSize(R.dimen.callkit_video_small_view_height)
            val aspectRatio = Rational(floatViewWidth, floatViewHeight)
            pictureInPictureParams.setAspectRatio(aspectRatio).build()
            val requestPipSuccess = this.enterPictureInPictureMode(pictureInPictureParams.build())
            if (!requestPipSuccess) {
                CallManager.instance.viewState.enterPipMode.set(false)
                return
            }
        } else {
            Logger.w(TAG, "current version (" + Build.VERSION.SDK_INT + ") does not support picture-in-picture")
        }
    }

    private fun hasPipModePermission(): Boolean {
        val appOpsManager = this.getSystemService(APP_OPS_SERVICE) as AppOpsManager
        val hasPipModePermission =
            (AppOpsManager.MODE_ALLOWED == appOpsManager.checkOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                this.applicationInfo.uid,
                this.packageName
            ))
        if (!hasPipModePermission) {
            AtomicToast.show(this, getString(R.string.callkit_enter_pip_mode_fail_hint), AtomicToast.Style.INFO)
        }
        return hasPipModePermission
    }

    private fun getEndCallHintText(reason: CallEndReason, userId: String): String? {
        val activeCall = CallStore.shared.observerState.activeCall.value
        val selfInfo = CallStore.shared.observerState.selfInfo.value
        if (activeCall.inviteeIds.size > 1 || activeCall.chatGroupId.isNotEmpty() || selfInfo.id == userId) {
            return null
        }
        return when (reason) {
            CallEndReason.Hangup -> getString(R.string.callkit_toast_other_party_hung_up)
            CallEndReason.Reject -> getString(R.string.callkit_toast_other_party_declined)
            CallEndReason.NoResponse -> getString(R.string.callkit_toast_other_party_no_response)
            CallEndReason.LineBusy -> getString(R.string.callkit_toast_other_party_busy)
            CallEndReason.Canceled -> getString(R.string.callkit_toast_other_party_cancelled)
            else -> null
        }
    }

    private fun handleCallEnded(reason: CallEndReason, userId: String) {
        val endHintText = getEndCallHintText(reason, userId)
        if (endHintText.isNullOrEmpty()) {
            finishCallMainActivity()
            return
        }
        showEndCallHint(endHintText)
    }

    private fun showEndCallHint(text: String) {
        val hintView = findHintView()
        if (hintView == null) {
            Logger.i(TAG, "showEndCallHint, hintView is null, finish directly")
            finishCallMainActivity()
            return
        }
        isShowingEndHint = true
        callViewContainer?.setOnTouchListener { _, _ -> true }
        hintView.playEndCallTransition(
            newText = text,
            holdDurationMs = CALL_END_HINT_HOLD_DURATION_MS
        ) {
            finishCallMainActivity()
        }
    }

    private fun findHintView(): HintView? {
        val callHintLayout = callView?.findViewById<FrameLayout>(R.id.rl_layout_call_hint)
        for (i in 0 until (callHintLayout?.childCount ?: 0)) {
            val child = callHintLayout?.getChildAt(i)
            if (child is HintView) {
                return child
            }
        }
        return null
    }

    override fun onBackPressed() {}

    private fun isCaller(userId: String): Boolean {
        val callerId = CallStore.shared.observerState.activeCall.value.inviterId
        return callerId == userId
    }

    private fun Activity.isInPipModeSafe(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                isInPictureInPictureMode
            } catch (e: Exception) {
                Logger.e(TAG, "isInPictureInPictureMode failed. {Device:${Build.MODEL},Exception:$e}")
                false
            }
        } else {
            false
        }
    }

    override fun onNotifyEvent(key: String?, subKey: String?, param: MutableMap<String?, Any?>) {
        if (TextUtils.equals(key, KEY_EXTENSION_NAME) && TextUtils.equals(subKey, NOTIFY_START_ACTIVITY)) {
            if (param.containsKey("requestCode")) {
                mStartActivityRequestCode = param["requestCode"] as? Int ?: 0
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    val intentToPickPic = Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
                    intentToPickPic.setDataAndType(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, PICK_CONTENT_ALL)
                    startActivityForResult(intentToPickPic, mStartActivityRequestCode)
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                            REQUEST_CODE_PERMISSIONS
                        )
                    }
                }
            }
        }
    }

    public override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val param: MutableMap<String?, Any?> = HashMap<String?, Any?>()
        param.put("requestCode", requestCode)
        param.put("resultCode", resultCode)
        param.put("data", data)
        TUICore.callService(KEY_EXTENSION_NAME, METHOD_ACTIVITY_RESULT, param)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String?>, grantResults: IntArray) {
        if (requestCode == REQUEST_CODE_PERMISSIONS) {
            val intentToPickPic = Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            intentToPickPic.setDataAndType(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, PICK_CONTENT_ALL)
            startActivityForResult(intentToPickPic, mStartActivityRequestCode)
        } else {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    companion object {
        private const val TAG = "CallMainActivity"
        private const val CALL_END_HINT_HOLD_DURATION_MS = 600L
        private const val KEY_EXTENSION_NAME: String = "TEBeautyExtension"
        private const val NOTIFY_START_ACTIVITY: String = "onStartActivityNotifyEvent"
        private const val METHOD_ACTIVITY_RESULT: String = "onActivityResult"
        private const val PICK_CONTENT_ALL: String = "image/*|video/*"
        private const val REQUEST_CODE_PERMISSIONS: Int = 1001

        private var mStartActivityRequestCode = 0
    }
}