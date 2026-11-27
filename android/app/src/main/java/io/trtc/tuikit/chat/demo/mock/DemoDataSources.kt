package io.trtc.tuikit.chat.demo.mock

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.trtc.tuikit.chat.demo.DemoSession
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.demo.login.PresetAccounts
import io.trtc.tuikit.chat.demo.social.DemoSessionBindings
import io.trtc.tuikit.chat.home.data.HomeDataSource
import io.trtc.tuikit.chat.home.data.HomeFeed
import io.trtc.tuikit.chat.home.data.HomePage
import io.trtc.tuikit.chat.home.data.HomeProfileFact
import io.trtc.tuikit.chat.home.data.HomeProfileInterest
import io.trtc.tuikit.chat.home.data.HomeProfilePost
import io.trtc.tuikit.chat.home.data.HomeSection
import io.trtc.tuikit.chat.home.data.HomeUserCard
import io.trtc.tuikit.chat.home.data.HomeUserDetail
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.mine.data.MineContent
import io.trtc.tuikit.chat.mine.data.MineDataSource
import io.trtc.tuikit.chat.mine.data.MineMenuItem
import io.trtc.tuikit.chat.mine.data.MineTag
import io.trtc.tuikit.chat.mine.data.MineWallet
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

class DemoHomeDataSource(context: Context) : HomeDataSource {
    private val app = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val alternate = HashSet<String>()

    private val heights: Map<String, Int> by lazy {
        val profiles = DemoFixtures.read(app, "profiles.json").optJSONObject("profiles") ?: return@lazy emptyMap()
        profiles.keys().asSequence().mapNotNull { id ->
            val facts = profiles.optJSONObject(id)?.optJSONArray("facts") ?: return@mapNotNull null
            val value = facts.optJSONObject(0)?.optString("v").orEmpty()
            value.removeSuffix("cm").toIntOrNull()?.let { id to it }
        }.toMap()
    }

    private val presetUserIds: List<String> by lazy { PresetAccounts.load(app).map { it.userId } }

    private class RawSection(val id: String, val title: String, val cards: List<HomeUserCard>, val altCards: List<HomeUserCard>)

    override fun loadFeed(completion: (Result<HomeFeed>) -> Unit) {
        run(completion) {
            alternate.clear()
            HomeFeed(
                city = DemoText.get(R.string.demo_shenzhen),
                sections = rawSections().map {
                    val page = page(it.cards, 0, "main")
                    HomeSection(it.id, it.title, page.cards, page.nextCursor)
                }
            )
        }
    }

    override fun refresh(sectionId: String, completion: (Result<HomePage>) -> Unit) {
        run(completion) {
            val section = rawSections().first { it.id == sectionId }
            val useAlt = if (alternate.remove(sectionId)) false else alternate.add(sectionId)
            if (useAlt && section.altCards.isNotEmpty()) page(section.altCards, 0, "alt") else page(section.cards, 0, "main")
        }
    }

    /** The cursor is `<order>:<offset>`; the demo pool (one fixture list) is cut into [PAGE_SIZE] cards per page. */
    override fun loadMore(sectionId: String, cursor: String, completion: (Result<HomePage>) -> Unit) {
        run(completion, delayMs = LOAD_MORE_LATENCY_MS) {
            val section = rawSections().first { it.id == sectionId }
            val (order, offset) = cursor.split(":").let { it[0] to it[1].toInt() }
            page(if (order == "alt" && section.altCards.isNotEmpty()) section.altCards else section.cards, offset, order)
        }
    }

    private fun page(all: List<HomeUserCard>, offset: Int, order: String): HomePage {
        val end = minOf(offset + PAGE_SIZE, all.size)
        return HomePage(all.subList(minOf(offset, end), end), if (end < all.size) "$order:$end" else null)
    }

    override fun loadUserDetail(userKey: String, completion: (Result<HomeUserDetail>) -> Unit) {
        run(completion) {
            val card = rawSections().flatMap { it.cards + it.altCards }.first { it.id == userKey }
            detail(card)
        }
    }

    private fun <T> run(completion: (Result<T>) -> Unit, delayMs: Long = 0L, work: () -> T) {
        executor.execute {
            val result = runCatching(work)
            main.postDelayed({ completion(result) }, delayMs)
        }
    }

    private companion object {
        const val PAGE_SIZE = 8
        const val LOAD_MORE_LATENCY_MS = 450L
        val PINNED_SECTIONS = setOf("recommend")
    }

    /**
     * Every IM demo account is listed except the one signed in on this device, so the Home tab always shows
     * the other people (the card of your own account would only open a chat with yourself).
     */
    private fun rawSections(): List<RawSection> {
        val bindings = bindings()
        val self = DemoSession.accountId
        val json = DemoFixtures.read(app, "home.json").getJSONArray("sections")
        fun cards(array: JSONArray?): List<HomeUserCard> {
            if (array == null) return emptyList()
            val seen = HashSet<String>()
            return (0 until array.length()).mapNotNull { index ->
                val card = array.getJSONObject(index)
                val id = card.getString("fixtureId")
                if (!seen.add(id)) return@mapNotNull null
                val userId = DemoSessionBindings.peerOf(id) ?: bindings[id].orEmpty()
                if (userId.isNotEmpty() && userId == self) return@mapNotNull null
                HomeUserCard(
                    id = id,
                    userId = userId,
                    displayName = card.getString("displayName"),
                    age = card.optInt("age"),
                    sex = card.optString("sex", "f"),
                    city = card.optString("city"),
                    distanceKm = card.optDouble("distanceKm", 0.0),
                    height = heights[id] ?: 0,
                    tags = strings(card.optJSONArray("tags")),
                    activity = card.optString("activity"),
                    bio = card.optString("bio"),
                    photo = card.optString("photo"),
                    avatar = card.optString("avatar")
                )
            }
        }
        return (0 until json.length()).map { index ->
            val section = json.getJSONObject(index)
            val id = section.getString("id")
            val mainCards = cards(section.getJSONArray("cards")).let {
                if (id in PINNED_SECTIONS) pinPresetAccounts(it) else it
            }
            RawSection(
                id = id,
                title = section.getString("title"),
                cards = mainCards,
                altCards = cards(section.optJSONArray("altCards"))
            )
        }
    }

    private fun pinPresetAccounts(cards: List<HomeUserCard>): List<HomeUserCard> {
        if (presetUserIds.isEmpty()) return cards
        val rank = presetUserIds.withIndex().associate { (index, userId) -> userId to index }
        val (pinned, rest) = cards.partition { rank.containsKey(it.userId) }
        return pinned.sortedBy { rank.getValue(it.userId) } + rest
    }

    private fun bindings(): Map<String, String> {
        val json = DemoFixtures.read(app, "demo-peer-bindings.json").getJSONArray("bindings")
        return (0 until json.length()).associate { index ->
            val item = json.getJSONObject(index)
            item.getString("fixtureId") to item.optString("boundUserId")
        }
    }

    private fun detail(card: HomeUserCard): HomeUserDetail {
        val json: JSONObject? = DemoFixtures.read(app, "profiles.json").getJSONObject("profiles").optJSONObject(card.id)
        val album = json?.optJSONObject("album")
        val posts = json?.optJSONObject("posts")
        val match = json?.optJSONObject("match")
        return HomeUserDetail(
            card = card,
            meta = json?.optString("meta").orEmpty(),
            voiceSeconds = json?.optInt("voice") ?: 0,
            bio = json?.optString("bio").orEmpty(),
            interests = json?.optJSONArray("interests")?.let { items ->
                (0 until items.length()).map {
                    val item = items.getJSONObject(it)
                    HomeProfileInterest(item.getString("text"), item.optInt("level", 1))
                }
            }.orEmpty(),
            matchScore = match?.optInt("score") ?: 0,
            matchText = match?.optString("text").orEmpty(),
            facts = json?.optJSONArray("facts")?.let { items ->
                (0 until items.length()).map {
                    val item = items.getJSONObject(it)
                    HomeProfileFact(item.getString("v"), item.getString("l"))
                }
            }.orEmpty(),
            albumCount = album?.optInt("count") ?: 0,
            albumPhotos = strings(album?.optJSONArray("photos")),
            postCount = posts?.optInt("count") ?: 0,
            posts = posts?.optJSONArray("items")?.let { items ->
                (0 until items.length()).map {
                    val item = items.getJSONObject(it)
                    HomeProfilePost(
                        item.getString("id"), item.optString("sub"), item.getString("text"),
                        strings(item.optJSONArray("photos")), item.optString("topic"),
                        item.optInt("likes"), item.optInt("comments")
                    )
                }
            }.orEmpty()
        )
    }

    private fun strings(array: JSONArray?): List<String> =
        array?.let { (0 until it.length()).map { index -> it.getString(index) } }.orEmpty()
}

class DemoMineDataSource(context: Context) : MineDataSource {
    private val app = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun loadContent(completion: (Result<MineContent>) -> Unit) {
        executor.execute {
            val result = runCatching(::read)
            main.post { completion(result) }
        }
    }

    private fun read(): MineContent {
        val root = DemoFixtures.read(app, "mine.json")
        val profile = root.getJSONObject("mockProfile")
        val wallet = root.getJSONObject("wallet")
        val groups = root.getJSONArray("menuGroups")
        return MineContent(
            signature = profile.optString("signature"),
            city = profile.optString("city"),
            tags = profile.optJSONArray("tags")?.let { tags ->
                (0 until tags.length()).map {
                    val tag = tags.getJSONObject(it)
                    MineTag(tag.getString("type"), tag.getString("text"))
                }
            }.orEmpty(),
            editLabel = profile.optString("edit"),
            wallet = MineWallet(
                label = wallet.getString("label"),
                balance = wallet.getString("balance"),
                promo = wallet.getString("promo"),
                promoPre = wallet.getString("promoPre"),
                promoBonus = wallet.getString("promoBonus"),
                action = wallet.getString("action")
            ),
            menuGroups = (0 until groups.length()).map { groupIndex ->
                val group = groups.getJSONArray(groupIndex)
                (0 until group.length()).map { itemIndex ->
                    val item = group.getJSONObject(itemIndex)
                    MineMenuItem(item.getString("id"), item.optString("icon"), item.getString("title"), item.optString("value"))
                }
            }
        )
    }
}
