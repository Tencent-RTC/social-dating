package io.trtc.tuikit.chat.mine

import io.trtc.tuikit.chat.mine.data.MineDataSource
import android.app.Activity
import android.content.Context
import io.trtc.tuikit.chat.mine.data.MineMenuItem

object MineKit {
    private var source: MineDataSource? = null
    private var handler: MineActions? = null

    fun install(dataSource: MineDataSource, actions: MineActions) {
        source = dataSource
        handler = actions
    }

    val dataSource: MineDataSource
        get() = checkNotNull(source) { "MineKit.install must be called before the mine pages are opened" }

    val actions: MineActions
        get() = checkNotNull(handler) { "MineKit.install must be called before the mine pages are opened" }
}

interface MineActions {
    fun onWalletClick(context: Context) {}

    fun onMenuItemClick(context: Context, item: MineMenuItem) {}

    fun onEditProfileClick(context: Context): Boolean = true

    /** Whether the Mine tab offers 退出登录 (false in the logged-out preview). */
    fun isLogoutAvailable(): Boolean = false

    /** Called after the user confirmed; the host signs out of IM and returns to its login screen. */
    fun onLogout(context: Context) {}

    /** Opens the language bottom sheet; [onApplied] runs after a different language was chosen. */
    fun showLanguagePicker(activity: Activity, onApplied: () -> Unit) {}

    /** Opens the appearance (mode + palette) bottom sheet; [onApplied] runs after a change was applied. */
    fun showAppearancePicker(activity: Activity, onApplied: () -> Unit) {}

    /** Opens the「加好友」verification rule sheet; [onApplied] runs after the new rule was saved. */
    fun showFriendAddRulePicker(activity: Activity, onApplied: () -> Unit) {}
}
