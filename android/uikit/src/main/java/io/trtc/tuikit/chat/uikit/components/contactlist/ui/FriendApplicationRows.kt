package io.trtc.tuikit.chat.uikit.components.contactlist.ui

import io.trtc.tuikit.atomicxcore.api.contact.FriendApplicationInfo
import io.trtc.tuikit.atomicxcore.api.contact.FriendApplicationType

internal object FriendApplicationRows {
    fun received(items: List<FriendApplicationInfo>): List<FriendApplicationInfo> =
        items.filter { it.type != FriendApplicationType.SENT }
}

/**
 * AtomicXCore drops an application from `friendApplicationList` as soon as it is accepted, so the page keeps the
 * rows accepted during this visit (in memory only) and shows them as "已添加" after the live ones.
 */
internal class FriendApplicationAcceptedState {
    private val accepted = LinkedHashMap<String, FriendApplicationInfo>()

    fun markAccepted(application: FriendApplicationInfo) {
        accepted[application.userID] = application
    }

    fun isAccepted(userID: String): Boolean = userID in accepted

    fun merge(live: List<FriendApplicationInfo>): List<FriendApplicationInfo> {
        val liveIDs = live.map { it.userID }.toSet()
        return live + accepted.values.filter { it.userID !in liveIDs }
    }
}
