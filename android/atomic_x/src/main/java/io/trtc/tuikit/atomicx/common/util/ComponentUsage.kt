package io.trtc.tuikit.atomicx.common.util

import android.util.Log
import com.tencent.imsdk.v2.V2TIMManager
import com.tencent.imsdk.v2.V2TIMValueCallback
import io.trtc.tuikit.atomicxcore.api.login.LoginStatus
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

object ComponentUsage {
    const val SOCIAL = 1024
    const val SOCIAL_HOME = 10241
    const val SOCIAL_MESSAGES = 10242
    const val SOCIAL_CHAT = 10243
    const val SOCIAL_CALL = 10244

    private const val TAG = "ComponentUsage"
    private val watching = AtomicBoolean(false)
    private var logined = false

    @JvmStatic
    fun report(type: Int) {
        watchLogin()
        send(type)
    }

    private fun watchLogin() {
        if (!watching.compareAndSet(false, true)) return
        MainScope().launch {
            LoginStore.shared.loginState.loginStatus.collect { status ->
                val now = status == LoginStatus.LOGINED
                if (now && !logined) send(SOCIAL)
                logined = now
            }
        }
    }

    private fun send(type: Int) {
        val param = JSONObject().put("UIComponentType", type).toString()
        V2TIMManager.getInstance().callExperimentalAPI(
            "reportTUIFeatureUsage",
            param,
            object : V2TIMValueCallback<Any> {
                override fun onSuccess(value: Any?) = Unit

                override fun onError(code: Int, desc: String?) {
                    Log.w(TAG, "report $type failed: $code $desc")
                }
            }
        )
    }
}
