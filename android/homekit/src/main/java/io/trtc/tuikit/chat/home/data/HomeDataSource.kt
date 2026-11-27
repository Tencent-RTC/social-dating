package io.trtc.tuikit.chat.home.data

interface HomeDataSource {
    /** Cities, sections and the first page of every section. */
    fun loadFeed(completion: (Result<HomeFeed>) -> Unit)

    /**
     * Pull-to-refresh and "换一批": a fresh first page of [sectionId] that replaces what is on screen.
     * An empty page keeps the current list.
     */
    fun refresh(sectionId: String, completion: (Result<HomePage>) -> Unit)

    /**
     * The page after [cursor] (the `nextCursor` of the previous page). The page calls it while the user is still a few
     * rows away from the end, never twice for the same cursor at once, and appends the result (cards already shown are
     * skipped by `HomeUserCard.id`). A failure shows a retry row at the end of the list.
     */
    fun loadMore(sectionId: String, cursor: String, completion: (Result<HomePage>) -> Unit)

    fun loadUserDetail(userKey: String, completion: (Result<HomeUserDetail>) -> Unit)
}

data class HomeUserCard(
    val id: String,
    val userId: String,
    val displayName: String,
    val age: Int,
    val sex: String,
    val city: String,
    val distanceKm: Double,
    val height: Int = 0,
    val tags: List<String>,
    val activity: String,
    val bio: String,
    val photo: String,
    val avatar: String
)

/**
 * One page of a section. [nextCursor] is an opaque token that the data source hands back to `loadMore`;
 * `null` means this was the last page.
 */
data class HomePage(
    val cards: List<HomeUserCard>,
    val nextCursor: String? = null
)

/** [cards] is the first page; [nextCursor] continues it (`null` = nothing more to load). */
data class HomeSection(
    val id: String,
    val title: String,
    val cards: List<HomeUserCard>,
    val nextCursor: String? = null
)

data class HomeFeed(
    val city: String,
    val sections: List<HomeSection>
)

data class HomeProfileInterest(val text: String, val level: Int)

data class HomeProfileFact(val value: String, val label: String)

data class HomeProfilePost(
    val id: String,
    val sub: String,
    val text: String,
    val photos: List<String>,
    val topic: String,
    val likes: Int,
    val comments: Int
)

data class HomeUserDetail(
    val card: HomeUserCard,
    val meta: String,
    val voiceSeconds: Int,
    val bio: String,
    val interests: List<HomeProfileInterest>,
    val matchScore: Int,
    val matchText: String,
    val facts: List<HomeProfileFact>,
    val albumCount: Int,
    val albumPhotos: List<String>,
    val postCount: Int,
    val posts: List<HomeProfilePost>
)
