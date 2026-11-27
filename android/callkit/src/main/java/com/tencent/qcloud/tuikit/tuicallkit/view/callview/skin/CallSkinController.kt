package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.content.Context
import com.tencent.cloud.tuikit.engine.call.TUICallEngine
import com.tencent.cloud.tuikit.engine.common.TUICommonDefine
import com.tencent.qcloud.tuicore.permission.PermissionCallback
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.Constants.BLUR_LEVEL_CLOSE
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.Constants.BLUR_LEVEL_HIGH
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.Logger
import com.tencent.qcloud.tuikit.tuicallkit.view.callview.core.common.utils.PermissionRequest
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import io.trtc.tuikit.atomicxcore.api.device.AudioRoute
import io.trtc.tuikit.atomicxcore.api.device.DeviceStatus
import io.trtc.tuikit.atomicxcore.api.device.DeviceStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map

/**
 * What the skinned call controls need from the call engine. [RealCallSkinController] forwards to the
 * SDK exactly like the original TUICallKit control views did; [PreviewCallSkinController] keeps the
 * state locally so the page can be inspected without a call (debug preview only).
 */
interface CallSkinController {
    val isVideo: Boolean
    val micOn: Flow<Boolean>
    val cameraOn: Flow<Boolean>
    val speakerOn: Flow<Boolean>
    val blurAvailable: Boolean

    fun toggleMic()
    fun toggleCamera()
    fun toggleSpeaker()
    fun flipCamera()
    fun toggleBlur()
    fun hangup()
}

class RealCallSkinController(
    private val context: Context,
    override val isVideo: Boolean,
    override val blurAvailable: Boolean = true
) : CallSkinController {
    private val device get() = DeviceStore.shared()
    private var blurOn = false

    override val micOn: Flow<Boolean> = device.deviceState.microphoneStatus.map { it == DeviceStatus.ON }
    override val cameraOn: Flow<Boolean> = device.deviceState.cameraStatus.map { it == DeviceStatus.ON }
    override val speakerOn: Flow<Boolean> = device.deviceState.currentAudioRoute.map { it == AudioRoute.SPEAKERPHONE }

    override fun toggleMic() {
        if (device.deviceState.microphoneStatus.value == DeviceStatus.ON) device.closeLocalMicrophone()
        else device.openLocalMicrophone(null)
    }

    override fun toggleCamera() {
        if (device.deviceState.cameraStatus.value == DeviceStatus.ON) {
            device.closeLocalCamera()
            return
        }
        PermissionRequest.requestCameraPermission(context, object : PermissionCallback() {
            override fun onGranted() {
                device.openLocalCamera(device.deviceState.isFrontCamera.value, null)
            }

            override fun onDenied() {
                Logger.e("openCamera failed, errMsg: camera permission denied")
            }
        })
    }

    override fun toggleSpeaker() {
        if (device.deviceState.currentAudioRoute.value == AudioRoute.SPEAKERPHONE) device.setAudioRoute(AudioRoute.EARPIECE)
        else device.setAudioRoute(AudioRoute.SPEAKERPHONE)
    }

    override fun flipCamera() {
        device.switchCamera(!device.deviceState.isFrontCamera.value)
    }

    override fun toggleBlur() {
        blurOn = !blurOn
        val level = if (blurOn) BLUR_LEVEL_HIGH else BLUR_LEVEL_CLOSE
        TUICallEngine.createInstance(context).setBlurBackground(level, object : TUICommonDefine.Callback {
            override fun onSuccess() {
                Logger.i("setBlurBackground success.")
            }

            override fun onError(errCode: Int, errMsg: String?) {
                blurOn = false
                Logger.e("setBlurBackground failed, errCode: $errCode, errMsg: $errMsg")
            }
        })
    }

    override fun hangup() {
        CallStore.shared.hangup(null)
    }
}

/** Debug-only controller: local toggles, no SDK access. */
class PreviewCallSkinController(
    override val isVideo: Boolean,
    mic: Boolean = true,
    camera: Boolean = true,
    speaker: Boolean = true
) : CallSkinController {
    private val mic = MutableStateFlow(mic)
    private val camera = MutableStateFlow(camera)
    private val speaker = MutableStateFlow(speaker)
    override val micOn: Flow<Boolean> = this.mic
    override val cameraOn: Flow<Boolean> = this.camera
    override val speakerOn: Flow<Boolean> = this.speaker
    override val blurAvailable: Boolean = true

    override fun toggleMic() { mic.value = !mic.value }
    override fun toggleCamera() { camera.value = !camera.value }
    override fun toggleSpeaker() { speaker.value = !speaker.value }
    override fun flipCamera() {}
    override fun toggleBlur() {}
    override fun hangup() {}
}
