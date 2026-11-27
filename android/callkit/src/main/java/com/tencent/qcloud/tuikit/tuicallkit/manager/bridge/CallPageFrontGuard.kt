package com.tencent.qcloud.tuikit.tuicallkit.manager.bridge

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.tencent.qcloud.tuikit.tuicallkit.TUICallKitImpl
import com.tencent.qcloud.tuikit.tuicallkit.common.data.Logger
import com.tencent.qcloud.tuikit.tuicallkit.manager.CallManager
import com.tencent.qcloud.tuikit.tuicallkit.state.ViewState.ViewRouter
import com.tencent.qcloud.tuikit.tuicallkit.view.CallMainActivity
import com.trtc.tuikit.common.ui.floatwindow.FloatWindowManager
import io.trtc.tuikit.atomicx.common.permission.PermissionActivity
import io.trtc.tuikit.atomicxcore.api.call.CallParticipantStatus
import io.trtc.tuikit.atomicxcore.api.call.CallStore
import java.lang.ref.WeakReference
import java.util.WeakHashMap

internal object CallPageFrontGuard {
    private const val TAG = "CallPageFrontGuard"
    private const val DIAG = "PushDiag"
    private const val MAX_RELAUNCH = 2

    private val handler = Handler(Looper.getMainLooper())
    private val marks = WeakHashMap<Activity, Long>()
    private var seq = 0L
    private var appContext: Context? = null
    private var requestedCallId: String? = null
    private var requestMark = 0L
    private var relaunchCount = 0
    private var resumed: WeakReference<Activity>? = null
    private var callPage: WeakReference<CallMainActivity>? = null
    private var callPageResumed = false
    private var pendingCover: WeakReference<Activity>? = null
    private val relaunchCheck = Runnable { relaunchIfCovered() }

    fun onCallPageRequested(context: Context) {
        if (!isCalleeWaiting()) {
            return
        }
        val callId = currentCallId()
        appContext = context.applicationContext ?: context
        if (callId != requestedCallId) {
            requestedCallId = callId
            relaunchCount = 0
        }
        requestMark = ++seq
    }

    fun onActivityStarted(activity: Activity) {
        marks[activity] = ++seq
    }

    fun onActivityResumed(activity: Activity) {
        resumed = WeakReference(activity)
        if (activity is CallMainActivity) {
            callPage = WeakReference(activity)
            callPageResumed = true
            pendingCover = null
            handler.removeCallbacks(relaunchCheck)
            return
        }
        if (requestedCallId == null || activity is PermissionActivity || activity.isFinishing) {
            return
        }
        val mark = marks[activity] ?: Long.MAX_VALUE
        if (mark < requestMark) {
            return
        }
        pendingCover = WeakReference(activity)
        handler.removeCallbacks(relaunchCheck)
        handler.post(relaunchCheck)
    }

    fun onActivityPaused(activity: Activity) {
        marks[activity] = ++seq
        if (resumed?.get() === activity) {
            resumed = null
        }
        if (activity is CallMainActivity) {
            callPageResumed = false
        }
    }

    fun onActivityDestroyed(activity: Activity) {
        marks.remove(activity)
        if (callPage?.get() === activity) {
            callPage = null
            callPageResumed = false
        }
    }

    private fun relaunchIfCovered() {
        val cover = pendingCover?.get()
        pendingCover = null
        val callId = requestedCallId ?: return
        if (!isCalleeWaiting() || currentCallId() != callId) {
            requestedCallId = null
            return
        }
        if (cover == null || cover.isFinishing || resumed?.get() !== cover) {
            return
        }
        if (callPageResumed || isCallShownElsewhere() || relaunchCount >= MAX_RELAUNCH) {
            return
        }
        relaunchCount++
        Log.i(DIAG, "frontGuard: call page covered by ${cover.javaClass.simpleName}, relaunch #$relaunchCount")
        Logger.i(TAG, "call page covered by ${cover.javaClass.simpleName}, relaunch #$relaunchCount")
        TUICallKitImpl.createInstance(appContext ?: cover.applicationContext).startCallActivity()
    }

    private fun currentCallId(): String = CallStore.shared.observerState.activeCall.value.callId

    private fun isCalleeWaiting(): Boolean {
        val state = CallStore.shared.observerState
        val self = state.selfInfo.value
        return self.status == CallParticipantStatus.Waiting && self.id != state.activeCall.value.inviterId
    }

    private fun isCallShownElsewhere(): Boolean {
        if (FloatWindowManager.sharedInstance().isShowing) {
            return true
        }
        val router = CallManager.instance.viewState.router.get()
        if (router == ViewRouter.Banner || router == ViewRouter.FloatView) {
            return true
        }
        val page = callPage?.get() ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && page.isInPictureInPictureMode
    }
}
