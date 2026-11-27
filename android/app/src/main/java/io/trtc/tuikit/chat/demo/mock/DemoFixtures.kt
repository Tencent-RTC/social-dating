package io.trtc.tuikit.chat.demo.mock

import android.content.Context
import io.trtc.tuikit.chat.hostbase.DemoText
import org.json.JSONObject

/** Quick interaction chip shown above the chat input. */
data class DemoQuickChip(
    val id: String,
    val label: String,
    val icon: String,
    val kind: String,
    val summary: String,
    val payload: Map<String, Any>
)

/** One E4 more-panel tile. `action` is "card" (send chat.card) or "notice". */
data class DemoMoreItem(
    val id: String,
    val label: String,
    val tile: String,
    val badge: String?,
    val action: String,
    val kind: String,
    val summary: String,
    val notice: String,
    val payload: Map<String, Any>
)

data class DemoQuickAction(
    val id: String,
    val label: String,
    val icon: String,
    val iconOn: String?,
    val primary: Boolean,
    val dot: Boolean,
    val action: String,
    val kind: String,
    val summary: String,
    val payload: Map<String, Any>
)

/** Host content of the 1:1 chat settings page (S6); the SDK owns none of it. */
data class DemoChatSetting(
    val title: String,
    val profileTags: List<String>,
    val intimacyLabel: String,
    val intimacyBadge: String,
    val backgroundLabel: String,
    val nicknameLabel: String,
    val nicknameValue: String,
    val reportLabel: String,
    val footer: String,
    val mockNotice: String
)

/** One entry of the local gift catalogue; the value is display text only, never a price. */
data class DemoGift(val ref: String, val name: String, val value: Int, val unit: String, val icon: String)

data class DemoGiftPanel(
    val title: String,
    val sendText: String,
    val comboWindowMs: Long,
    val gifts: List<DemoGift>
)

data class DemoChatCopy(
    val safetyBanner: String,
    val defaultSubtitle: String,
    val quickChips: List<DemoQuickChip>,
    val morePanel: List<DemoMoreItem> = emptyList(),
    val quickActions: List<DemoQuickAction> = emptyList(),
    val inputPlaceholder: String = "",
    val sendText: String = "",
    val chatSetting: DemoChatSetting? = null,
    val giftPanel: DemoGiftPanel? = null
)

object DemoFixtures {
    fun chat(context: Context): DemoChatCopy {
        val root = read(context, "chat.json")
        val chips = root.getJSONArray("quickChips")
        val inputBar = root.optJSONObject("inputBar") ?: JSONObject()
        return DemoChatCopy(
            safetyBanner = root.optString("safetyBanner"),
            defaultSubtitle = root.optString("defaultSubtitle"),
            inputPlaceholder = inputBar.optString("placeholder"),
            sendText = inputBar.optString("sendText"),
            chatSetting = root.optJSONObject("chatSetting")?.let { setting ->
                val tags = setting.optJSONArray("profileTags")
                DemoChatSetting(
                    title = setting.optString("title"),
                    profileTags = tags?.let { array -> (0 until array.length()).map { array.getString(it) } }.orEmpty(),
                    intimacyLabel = setting.optString("intimacyLabel"),
                    intimacyBadge = setting.optString("intimacyBadge"),
                    backgroundLabel = setting.optString("backgroundLabel"),
                    nicknameLabel = setting.optString("nicknameLabel"),
                    nicknameValue = setting.optString("nicknameValue"),
                    reportLabel = setting.optString("reportLabel"),
                    footer = setting.optString("footer"),
                    mockNotice = setting.optString("mockNotice")
                )
            },
            giftPanel = root.optJSONObject("giftPanel")?.let { panel ->
                val items = panel.optJSONArray("gifts")
                DemoGiftPanel(
                    title = panel.optString("title"),
                    sendText = panel.optString("sendText"),
                    comboWindowMs = panel.optLong("comboWindowMs", 2600L),
                    gifts = items?.let { array ->
                        (0 until array.length()).map { index ->
                            val gift = array.getJSONObject(index)
                            DemoGift(
                                ref = gift.getString("ref"),
                                name = gift.getString("name"),
                                value = gift.optInt("value"),
                                unit = gift.optString("unit"),
                                icon = gift.optString("icon")
                            )
                        }
                    }.orEmpty()
                )
            },
            quickActions = root.optJSONArray("quickActions")?.let { items ->
                (0 until items.length()).map { index ->
                    val item = items.getJSONObject(index)
                    val payloadJson = item.optJSONObject("payload") ?: JSONObject()
                    DemoQuickAction(
                        id = item.getString("id"),
                        label = item.getString("label"),
                        icon = item.getString("icon"),
                        iconOn = item.optString("iconOn").takeIf { it.isNotBlank() },
                        primary = item.optBoolean("primary"),
                        dot = item.optBoolean("dot"),
                        action = item.getString("action"),
                        kind = item.optString("kind"),
                        summary = item.optString("summary"),
                        payload = payloadJson.keys().asSequence().associateWith { key -> payloadJson.get(key) }
                    )
                }
            }.orEmpty(),
            quickChips = (0 until chips.length()).map { index ->
                val item = chips.getJSONObject(index)
                val payloadJson = item.optJSONObject("payload") ?: JSONObject()
                DemoQuickChip(
                    id = item.getString("id"),
                    label = item.getString("label"),
                    icon = item.optString("icon"),
                    kind = item.getString("kind"),
                    summary = item.optString("summary"),
                    payload = payloadJson.keys().asSequence().associateWith { key -> payloadJson.get(key) }
                )
            },
            morePanel = root.optJSONArray("morePanel")?.let { items ->
                (0 until items.length()).map { index ->
                    val item = items.getJSONObject(index)
                    val payloadJson = item.optJSONObject("payload") ?: JSONObject()
                    DemoMoreItem(
                        id = item.getString("id"),
                        label = item.getString("label"),
                        tile = item.getString("tile"),
                        badge = item.optString("badge").takeIf { it.isNotBlank() },
                        action = item.getString("action"),
                        kind = item.optString("kind"),
                        summary = item.optString("summary"),
                        notice = item.optString("notice"),
                        payload = payloadJson.keys().asSequence().associateWith { key -> payloadJson.get(key) }
                    )
                }
            }.orEmpty()
        )
    }

    fun read(context: Context, name: String): JSONObject =
        context.assets.open("demo-fixtures/$name").use {
            JSONObject(it.bufferedReader(Charsets.UTF_8).readText())
        }.also { resolveStringRefs(it) }

    /**
     * Fixture copy that is UI text (labels, banners, menu titles) is stored as `@demo_...` resource references so the
     * JSON stays language neutral; this swaps each reference for the string of the current language.
     */
    private fun resolveStringRefs(node: Any?) {
        when (node) {
            is JSONObject -> node.keys().asSequence().toList().forEach { key ->
                val value = node.get(key)
                if (value is String && value.startsWith(STRING_REF)) node.put(key, DemoText.byName(value.substring(1)))
                else resolveStringRefs(value)
            }
            is org.json.JSONArray -> for (index in 0 until node.length()) {
                val value = node.get(index)
                if (value is String && value.startsWith(STRING_REF)) node.put(index, DemoText.byName(value.substring(1)))
                else resolveStringRefs(value)
            }
        }
    }

    private const val STRING_REF = "@demo_"
}
