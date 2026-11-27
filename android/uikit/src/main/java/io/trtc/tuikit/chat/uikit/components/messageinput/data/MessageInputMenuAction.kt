package io.trtc.tuikit.chat.uikit.components.messageinput.data

import android.content.Context
import io.trtc.tuikit.chat.uikit.components.common.uicustom.CustomItem
import io.trtc.tuikit.chat.uikit.components.common.uicustom.EditorContext

object MessageInputActionIDs {
    const val ALBUM = "messageInput.album"
    const val TAKE_PHOTO = "messageInput.takePhoto"
    const val RECORD_VIDEO = "messageInput.recordVideo"
    const val FILE = "messageInput.file"
    const val VIDEO_CALL = "messageInput.videoCall"
    const val AUDIO_CALL = "messageInput.audioCall"
}

data class MessageInputMenuAction(
    override val ID: String,
    val title: String = "",
    val iconResID: Int = 0,
    val dangerous: Boolean = false,
    val onClick: () -> Unit = {},
    val showRedDot: Boolean = false,
    /** The icon is a complete tile bitmap: fill the tile, no tint, no tile background. */
    val fullBleedIcon: Boolean = false,
    /** Short pill label (e.g. "NEW") on the tile's top edge; dismissed on tap like the red dot. */
    val badgeText: String? = null,
) : CustomItem

data class MessageInputMenuActionContext(
    override val androidContext: Context,
    val conversationID: String,
): EditorContext
