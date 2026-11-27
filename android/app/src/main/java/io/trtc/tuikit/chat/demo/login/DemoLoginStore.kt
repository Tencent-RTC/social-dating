package io.trtc.tuikit.chat.demo.login

import android.content.Context
import com.tencent.mmkv.MMKV
import io.trtc.tuikit.chat.demo.mock.DemoFixtures

internal data class SavedLogin(val sdkAppId: Int, val userId: String)

internal object DemoLoginStore {
    private const val STORE_ID = "chat1v1_login"
    private const val KEY_SDK_APP_ID = "sdk_app_id"
    private const val KEY_USER_ID = "user_id"

    private var store: MMKV? = null

    fun init(context: Context) {
        MMKV.initialize(context.applicationContext)
        store = MMKV.mmkvWithID(STORE_ID)
    }

    fun save(sdkAppId: Int, userId: String) {
        val kv = store ?: return
        kv.encode(KEY_SDK_APP_ID, sdkAppId)
        kv.encode(KEY_USER_ID, userId)
    }

    fun load(): SavedLogin? {
        val kv = store ?: return null
        val userId = kv.decodeString(KEY_USER_ID, "").orEmpty()
        val sdkAppId = kv.decodeInt(KEY_SDK_APP_ID, 0)
        if (userId.isEmpty() || sdkAppId <= 0) return null
        return SavedLogin(sdkAppId, userId)
    }

    fun clear() {
        store?.clearAll()
    }
}

internal object PresetAccounts {
    data class Entry(val userId: String, val name: String, val avatarUrl: String)

    fun load(context: Context): List<Entry> {
        val list = DemoFixtures.read(context, "login-presets.json").getJSONArray("presets")
        return (0 until list.length()).map {
            val item = list.getJSONObject(it)
            Entry(item.getString("userId"), item.getString("name"), item.getString("avatar"))
        }
    }
}
