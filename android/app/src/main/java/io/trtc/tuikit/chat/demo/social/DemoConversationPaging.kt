package io.trtc.tuikit.chat.demo.social

import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationListStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationLoadOption

/** A conversation list the SDK hands out one page at a time. */
interface PagedConversations {
    val hasMore: Boolean
    fun reload(done: (Boolean) -> Unit)
    fun loadMore(done: (Boolean) -> Unit)
}

/**
 * Badges and bulk operations must see every member, not the first 100: this walks the pages until the SDK
 * reports the end. A page cap keeps a misbehaving list from looping forever, and [shouldContinue] lets a
 * newer load supersede an older chain.
 */
object DemoConversationPaging {
    const val MAX_PAGES = 50

    fun loadAll(
        source: PagedConversations,
        shouldContinue: () -> Boolean = { true },
        onDone: (Boolean) -> Unit = {}
    ) {
        source.reload { ok -> if (ok) loadRest(source, 1, shouldContinue, onDone) else onDone(false) }
    }

    private fun loadRest(source: PagedConversations, loaded: Int, shouldContinue: () -> Boolean, onDone: (Boolean) -> Unit) {
        if (!source.hasMore) return onDone(true)
        if (loaded >= MAX_PAGES || !shouldContinue()) return onDone(false)
        source.loadMore { ok -> if (ok) loadRest(source, loaded + 1, shouldContinue, onDone) else onDone(false) }
    }
}

/**
 * One live paging chain per list: a newer [load] supersedes the chain in flight, so pages of two
 * overlapping loads are never requested interleaved from the same store.
 */
class PagedConversationLoader(private val source: PagedConversations) {
    private var generation = 0

    fun load(onDone: (Boolean) -> Unit = {}) {
        val mine = ++generation
        DemoConversationPaging.loadAll(source, shouldContinue = { mine == generation }, onDone = onDone)
    }
}

/** Real paging over a [ConversationListStore]; failures are recorded instead of swallowed. */
class SdkPagedConversations(
    private val store: ConversationListStore,
    private val option: ConversationLoadOption = ConversationLoadOption()
) : PagedConversations {
    override val hasMore: Boolean get() = store.state.hasMoreConversations.value

    override fun reload(done: (Boolean) -> Unit) =
        store.loadConversations(option.copy(), handler("loadConversations", done))

    override fun loadMore(done: (Boolean) -> Unit) =
        store.loadMoreConversations(handler("loadMoreConversations", done))

    private fun handler(operation: String, done: (Boolean) -> Unit) = object : CompletionHandler {
        override fun onSuccess() = done(true)

        override fun onFailure(code: Int, desc: String) {
            DemoGroupDiagnostics.record(operation, GroupOpResult.failed(code, desc))
            done(false)
        }
    }
}
