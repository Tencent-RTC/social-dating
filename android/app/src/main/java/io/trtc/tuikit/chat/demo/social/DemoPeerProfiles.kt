package io.trtc.tuikit.chat.demo.social

import android.content.Context
import io.trtc.tuikit.chat.demo.mock.DemoFixtures
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.R as BaseR
import org.json.JSONArray
import org.json.JSONObject
import android.view.Gravity
import android.widget.LinearLayout
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.TagKind
import com.tencent.imsdk.v2.V2TIMManager
import com.tencent.imsdk.v2.V2TIMUserFullInfo
import com.tencent.imsdk.v2.V2TIMValueCallback
import io.trtc.tuikit.chat.hostbase.HostThread
import java.util.concurrent.ConcurrentHashMap

data class DemoPeerProfile(
    val fixtureId: String,
    val userId: String,
    val name: String,
    val age: Int,
    val sex: String,
    val city: String,
    val distanceKm: Double,
    val height: Int,
    val activity: String,
    val avatar: String,
    val score: Int,
    val matchText: String,
    val interests: List<String>
) {
    val subtitle: String get() = DemoPeerProfiles.subtitle(city, height, age)
}

object DemoPeerProfiles {
    fun subtitle(city: String, height: Int, age: Int): String = listOf(
        city,
        if (height > 0) DemoText.get(BaseR.string.demo_height_cm, height.toString()) else "",
        if (age > 0) DemoText.get(BaseR.string.demo_age_years, age.toString()) else ""
    ).filter { it.isNotBlank() }.joinToString(" · ")

    fun forUser(context: Context, userId: String): DemoPeerProfile? {
        if (userId.isBlank()) return null
        val app = context.applicationContext
        val bound = bindings(app)
        val fixtureId = bound.entries.firstOrNull { it.value == userId }?.key
            ?: DemoSessionBindings.fixtureOf(userId)
            ?: return null
        return forFixture(app, fixtureId, userId)
    }

    fun forFixture(context: Context, fixtureId: String, userId: String = ""): DemoPeerProfile? {
        val app = context.applicationContext
        val card = findCard(app, fixtureId) ?: return null
        val profile = DemoFixtures.read(app, "profiles.json").getJSONObject("profiles").optJSONObject(fixtureId)
        val match = profile?.optJSONObject("match")
        val height = profile?.optJSONArray("facts")
            ?.optJSONObject(0)?.optString("v")?.removeSuffix("cm")?.toIntOrNull() ?: 0
        val interests = profile?.optJSONArray("interests")?.let { items ->
            (0 until items.length()).map { items.getJSONObject(it).optString("text") }
        }.orEmpty().ifEmpty { strings(card.optJSONArray("tags")) }
        return DemoPeerProfile(
            fixtureId = fixtureId,
            userId = userId.ifBlank { DemoSessionBindings.peerOf(fixtureId) ?: bindings(app)[fixtureId].orEmpty() },
            name = card.optString("displayName"),
            age = card.optInt("age"),
            sex = card.optString("sex", "f"),
            city = card.optString("city"),
            distanceKm = card.optDouble("distanceKm", 0.0),
            height = height,
            activity = card.optString("activity"),
            avatar = card.optString("avatar"),
            score = match?.optInt("score") ?: 0,
            matchText = match?.optString("text").orEmpty(),
            interests = interests.filter { it.isNotBlank() }
        )
    }

    private fun findCard(context: Context, fixtureId: String): JSONObject? {
        val sections = DemoFixtures.read(context, "home.json").getJSONArray("sections")
        for (index in 0 until sections.length()) {
            val section = sections.getJSONObject(index)
            for (key in listOf("cards", "altCards")) {
                val cards = section.optJSONArray(key) ?: continue
                for (cardIndex in 0 until cards.length()) {
                    val card = cards.getJSONObject(cardIndex)
                    if (card.optString("fixtureId") == fixtureId) return card
                }
            }
        }
        return null
    }

    private fun bindings(context: Context): Map<String, String> {
        val json = DemoFixtures.read(context, "demo-peer-bindings.json").getJSONArray("bindings")
        return (0 until json.length()).associate {
            val item = json.getJSONObject(it)
            item.getString("fixtureId") to item.optString("boundUserId")
        }
    }

    private fun strings(array: JSONArray?): List<String> =
        array?.let { (0 until it.length()).map { index -> it.getString(index) } }.orEmpty()
}

object DemoPeerTags {
    private val cache = HashMap<String, DemoPeerProfile?>()

    fun inline(context: Context, peerId: String, heightDp: Int = HostMetrics.SEX_TAG_H): LinearLayout? {
        if (peerId.isBlank()) return null
        val profile = profile(context, peerId) ?: return null
        return build(context, profile, heightDp)
    }

    /** Everything the demo knows about the peer — city, age, height — for the friend-application detail page. */
    fun full(context: Context, peerId: String, heightDp: Int = HostMetrics.SEX_TAG_H): LinearLayout? {
        if (peerId.isBlank()) return null
        val profile = profile(context, peerId) ?: return null
        val row = build(context, profile, heightDp) ?: return null
        if (profile.height > 0) {
            row.addView(Host.kindTag(context, TagKind.HEIGHT, DemoText.get(BaseR.string.demo_height_cm, profile.height.toString()),
                heightDp, 8f),
                LinearLayout.LayoutParams(-2, Host.dp(context, heightDp)).apply {
                    if (row.childCount > 0) marginStart = Host.dp(context, 4)
                })
        }
        return row
    }

    private fun profile(context: Context, peerId: String): DemoPeerProfile? = cache.getOrPut(peerId) {
        runCatching { DemoPeerProfiles.forUser(context.applicationContext, peerId) }.getOrNull()
    }

    fun build(context: Context, profile: DemoPeerProfile, heightDp: Int = HostMetrics.SEX_TAG_H): LinearLayout? {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        if (profile.age > 0) {
            row.addView(Host.sexTag(context, profile.sex, profile.age),
                LinearLayout.LayoutParams(-2, Host.dp(context, HostMetrics.SEX_TAG_H)))
        }
        if (profile.city.isNotBlank()) {
            row.addView(Host.kindTag(context, TagKind.CITY, profile.city, heightDp, 8f),
                LinearLayout.LayoutParams(-2, Host.dp(context, heightDp)).apply {
                    if (row.childCount > 0) marginStart = Host.dp(context, 4)
                })
        }
        return row.takeIf { it.childCount > 0 }
    }
}

/**
 * Process-wide IM profile cache (nickname / avatar / signature by userID).
 *
 * A conversation list, the call records and the message banner all show the same peers, so a profile is fetched once
 * per run instead of once per page — which is what let the call list paint a userID first and fill in the nickname a
 * moment later.
 */
object DemoUserProfileCache {
    private val cache = ConcurrentHashMap<String, V2TIMUserFullInfo>()

    fun get(userID: String): V2TIMUserFullInfo? = cache[userID]

    fun put(info: V2TIMUserFullInfo) {
        if (info.userID.isNotBlank()) cache[info.userID] = info
    }

    /**
     * Fetches the ids that are not cached yet. [onDone] runs on the main thread and is called even when the request
     * fails, so a caller waiting to paint cannot be left hanging.
     */
    fun load(ids: Collection<String>, onDone: () -> Unit) {
        val missing = ids.filter { it.isNotBlank() && cache[it] == null }.distinct()
        if (missing.isEmpty()) {
            onDone()
            return
        }
        V2TIMManager.getInstance().getUsersInfo(missing, object : V2TIMValueCallback<List<V2TIMUserFullInfo>> {
            override fun onSuccess(data: List<V2TIMUserFullInfo>?) {
                data?.forEach { cache[it.userID] = it }
                HostThread.runOnMain { onDone() }
            }

            override fun onError(code: Int, desc: String?) {
                HostThread.runOnMain { onDone() }
            }
        })
    }
}
