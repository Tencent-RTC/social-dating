package com.tencent.qcloud.tuikit.tuicallkit.manager.bridge

import io.trtc.tuikit.atomicxcore.api.login.LoginStatus
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * Follows AtomicXCore [LoginStore] instead of TUILogin events.
 *
 * The app signs in through LoginStore only, and TUILogin events are emitted by TUILogin itself, so
 * they never fire here. LoginStore moves to LOGINED after login succeeds and back to UNLOGIN on
 * logout, kick-off or userSig expiry. Its initial value is UNLOGIN, so [onLogout] is only called
 * after an [onLogin]; callbacks run on the main thread.
 */
internal class LoginStatusWatcher(
    private val onLogin: () -> Unit,
    private val onLogout: () -> Unit,
) {
    private val scope = MainScope()
    private var started = false
    private var logined = false

    fun start() {
        if (started) return
        started = true
        scope.launch {
            LoginStore.shared.loginState.loginStatus.collect { status ->
                if (status == LoginStatus.LOGINED) {
                    if (!logined) {
                        logined = true
                        onLogin()
                    }
                } else if (logined) {
                    logined = false
                    onLogout()
                }
            }
        }
    }
}
