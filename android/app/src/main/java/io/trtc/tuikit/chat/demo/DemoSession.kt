package io.trtc.tuikit.chat.demo

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.trtc.tuikit.atomicxcore.api.login.LoginListener
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import io.trtc.tuikit.chat.demo.host.DemoMineActions
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.HostDiagnostics

object DemoSession {
    @Volatile
    var accountId: String = ""

    @Volatile
    var callReady: Boolean = false

    @Volatile
    var preview: Boolean = false

    @Volatile
    var activeConversationId: String = ""
}

internal object DemoSessionWatcher {
    private val handler = Handler(Looper.getMainLooper())
    private var appContext: Context? = null

    private val listener = object : LoginListener() {
        override fun onKickedOffline() {
            handler.post { end("kicked", R.string.demo_session_kicked_offline) }
        }

        override fun onLoginExpired() {
            handler.post { end("expired", R.string.demo_session_expired) }
        }
    }

    fun install(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        LoginStore.shared.addLoginListener(listener)
    }

    private fun end(reason: String, messageRes: Int) {
        val app = appContext ?: return
        if (DemoSession.preview || DemoSession.accountId.isEmpty()) return
        HostDiagnostics.record("session.$reason", 0, DemoSession.accountId)
        DemoMineActions.finishLogout(app, DemoText.get(messageRes))
    }
}
