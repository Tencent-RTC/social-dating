package io.trtc.tuikit.chat.hostbase

import android.content.Context
import android.util.Log

object HostNotifyPrefs {
    const val FILE = "demo_settings"
    const val KEY_MESSAGE = "notify_message"
    const val KEY_SOUND = "notify_sound"

    fun messageAlerts(context: Context): Boolean =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_MESSAGE, true)

    fun sound(context: Context): Boolean =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_SOUND, true)
}

/** Error codes go to the log only; they are never shown to users. */
object HostDiagnostics {
    @Volatile
    var logger: (String) -> Unit = { line -> runCatching { Log.w("Chat1v1", line) } }

    fun record(tag: String, code: Int = 0, message: String = "") {
        val codePart = if (code != 0) " code=$code" else ""
        val messagePart = if (message.isNotBlank()) " $message" else ""
        logger("$tag$codePart$messagePart")
    }
}
