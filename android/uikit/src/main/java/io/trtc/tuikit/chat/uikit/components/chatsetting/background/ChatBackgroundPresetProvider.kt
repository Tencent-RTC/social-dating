package io.trtc.tuikit.chat.uikit.components.chatsetting.background

import androidx.annotation.StringRes
import io.trtc.tuikit.chat.uikit.R

data class ChatBackgroundPresetItem(
    val imageUri: String?,
    val thumbnailUri: String?,
    /** Display name shown over the thumbnail; 0 for the 「默认」 cell, which draws its own label. */
    @StringRes val nameRes: Int = 0
) {
    val isDefault: Boolean
        get() = imageUri == null
}

/**
 * The eight preset chat backgrounds shipped inside the app (assets/chat_bg, 1080x2340 + 288x624 thumbnails).
 * A chosen preset is stored as `preset://<id>`; [resolve] turns it into a Glide-loadable asset URI.
 * Older stored values (SDK online images, custom URLs) keep working because they pass through [resolve] unchanged.
 */
object ChatBackgroundPresetProvider {
    private const val SCHEME = "preset://"
    private const val ASSET_ROOT = "file:///android_asset/chat_bg/"

    /** Dark four first, then the light four; the order is the order in the picker. */
    private val DARK_IDS = listOf("night", "heart", "neon", "still")
    private val LIGHT_IDS = listOf("breeze", "mint", "peach", "salt")

    private val NAMES = mapOf(
        "night" to R.string.chat_background_preset_night,
        "heart" to R.string.chat_background_preset_heart,
        "neon" to R.string.chat_background_preset_neon,
        "still" to R.string.chat_background_preset_still,
        "breeze" to R.string.chat_background_preset_breeze,
        "mint" to R.string.chat_background_preset_mint,
        "peach" to R.string.chat_background_preset_peach,
        "salt" to R.string.chat_background_preset_salt
    )

    fun getPresetItems(): List<ChatBackgroundPresetItem> {
        val items = ArrayList<ChatBackgroundPresetItem>(DARK_IDS.size + LIGHT_IDS.size + 1)
        items.add(ChatBackgroundPresetItem(imageUri = null, thumbnailUri = null))
        for (id in DARK_IDS + LIGHT_IDS) {
            items.add(ChatBackgroundPresetItem(
                imageUri = SCHEME + id,
                thumbnailUri = ASSET_ROOT + "thumb_$id.jpg",
                nameRes = NAMES.getValue(id)
            ))
        }
        return items
    }

    /** The model Glide should load for a stored background value. */
    fun resolve(uri: String): String {
        val id = presetId(uri) ?: return uri
        return ASSET_ROOT + "bg_$id.jpg"
    }

    /** True for the light-coloured presets, which get a dark scrim while the UI is in dark mode. */
    fun isLightPreset(uri: String): Boolean = presetId(uri) in LIGHT_IDS

    private fun presetId(uri: String): String? =
        if (uri.startsWith(SCHEME)) uri.removePrefix(SCHEME) else null
}
