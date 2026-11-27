package io.trtc.tuikit.chat.uikit.components.messagelist.ui.reactions

import androidx.annotation.StringRes
import io.trtc.tuikit.chat.uikit.R

/**
 * 表情回应操作失败时的错误码 -> 文案映射。
 *
 * IM SDK 在单条消息 Reaction 数量超限、单个 Reaction 用户数量超限时会回调
 * onFailure，这里统一转换成用户可见的提示文案，避免失败后没有任何反馈。
 */
internal object MessageReactionErrorPolicy {
    private const val ERR_SVR_MSG_REACTION_COUNT_LIMIT = 23005
    private const val ERR_SVR_MSG_REACTION_USER_COUNT_LIMIT = 23006

    @StringRes
    fun resolveAddFailureMessageResId(errorCode: Int): Int {
        return when (errorCode) {
            ERR_SVR_MSG_REACTION_COUNT_LIMIT -> R.string.message_list_reaction_count_limit
            ERR_SVR_MSG_REACTION_USER_COUNT_LIMIT -> R.string.message_list_reaction_user_count_limit
            else -> R.string.message_list_reaction_failed
        }
    }
}
