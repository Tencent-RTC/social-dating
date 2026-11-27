package io.trtc.tuikit.chat.home

import io.trtc.tuikit.chat.home.data.HomeDataSource
import io.trtc.tuikit.chat.home.data.HomeUserDetail
import android.content.Context
import io.trtc.tuikit.chat.home.data.HomeProfilePost
import io.trtc.tuikit.chat.home.data.HomeUserCard

object HomeKit {
    private var source: HomeDataSource? = null
    private var handler: HomeActions? = null
    private val details = HashMap<String, HomeUserDetail>()

    fun install(dataSource: HomeDataSource, actions: HomeActions) {
        source = dataSource
        handler = actions
        details.clear()
    }

    val dataSource: HomeDataSource
        get() = checkNotNull(source) { "HomeKit.install must be called before the home pages are opened" }

    val actions: HomeActions
        get() = checkNotNull(handler) { "HomeKit.install must be called before the home pages are opened" }

    fun cachedDetail(userKey: String): HomeUserDetail? = details[userKey]

    fun cacheDetail(userKey: String, detail: HomeUserDetail) {
        details[userKey] = detail
    }

    fun clearCache() = details.clear()
}

/** Result of the one-tap friend request: added right away, or waiting for the other side to approve. */
enum class FriendAddOutcome { ADDED, PENDING, FAILED }

interface HomeActions {
    fun onOpenChat(context: Context, user: HomeUserCard) {}

    /** Sends the preset friend request (no remark, default wording); never opens the add-friend form. */
    fun onAddFriend(context: Context, user: HomeUserCard, onResult: (FriendAddOutcome) -> Unit = {}) {}

    fun isFriend(context: Context, user: HomeUserCard, onResult: (Boolean) -> Unit) {
        onResult(false)
    }

    /** Removes the friend relation; [onResult] is true once the delete call succeeded. */
    fun onDeleteFriend(context: Context, user: HomeUserCard, onResult: (Boolean) -> Unit) {
        onResult(false)
    }

    fun onVideoChat(context: Context, user: HomeUserCard)

    fun onVoiceSignatureClick(context: Context, user: HomeUserCard) {}

    fun onMoreClick(context: Context, user: HomeUserCard) {}

    fun onAlbumPhotoClick(context: Context, user: HomeUserCard, photo: String) {}

    fun onCommentClick(context: Context, user: HomeUserCard, post: HomeProfilePost) {}
}
