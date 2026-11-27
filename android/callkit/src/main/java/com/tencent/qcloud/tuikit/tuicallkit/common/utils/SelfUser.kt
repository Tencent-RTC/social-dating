package com.tencent.qcloud.tuikit.tuicallkit.common.utils

import com.tencent.imsdk.v2.V2TIMManager
import io.trtc.tuikit.atomicxcore.api.login.LoginStore

/**
 * The signed-in user, read from AtomicXCore [LoginStore] (TUILogin is not used by the app, so its
 * getters are empty). The user ID falls back to V2TIM in case LoginStore has not filled the
 * profile yet.
 */
internal object SelfUser {
    val userId: String
        get() {
            val fromStore = LoginStore.shared.loginState.loginUserInfo.value?.userID.orEmpty()
            if (fromStore.isNotEmpty()) return fromStore
            return V2TIMManager.getInstance().loginUser.orEmpty()
        }

    val nickname: String
        get() = LoginStore.shared.loginState.loginUserInfo.value?.nickname.orEmpty()

    val avatarUrl: String
        get() = LoginStore.shared.loginState.loginUserInfo.value?.avatarURL.orEmpty()
}
