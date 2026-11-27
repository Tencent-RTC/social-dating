package io.trtc.tuikit.chat.demo.social

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.contact.ContactStore
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationInfo
import io.trtc.tuikit.atomicxcore.api.conversation.ConversationListStore
import io.trtc.tuikit.atomicxcore.api.message.MessageListStore
import io.trtc.tuikit.atomicxcore.api.message.MessageLoadOption
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import android.util.Log
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.HostDiagnostics
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import io.trtc.tuikit.atomicx.common.util.NotifyParams
import io.trtc.tuikit.atomicx.common.util.TUIObserver
import io.trtc.tuikit.atomicx.common.util.TUIEventBus

interface GreetingPorts {
    fun inspect(conversationId: String, done: (Boolean?) -> Unit)
    fun setGreeting(ids: List<String>, greeting: Boolean, done: (GroupOpResult) -> Unit)
    fun loadFriends(done: (Set<String>?) -> Unit)
}

interface DecidedStore {
    fun load(): Set<String>
    fun save(ids: Set<String>)
}

class DemoGroupWatch(
    private val ports: GreetingPorts,
    private val store: DecidedStore,
    private val isDisabled: () -> Boolean = { DemoGroupDiagnostics.packageUnsupported },
    private val schedule: (Long, () -> Unit) -> Unit = { _, _ -> },
    private val onChange: (GreetingContext) -> Unit = {}
) {
    private val decided = store.load().toMutableSet()
    private var friends: Set<String>? = null
    private var friendsFailed = false
    private var friendsLoading = false
    private var friendsRetryPending = false
    private var friendsRetryDelay = FRIENDS_RETRY_FIRST_MS
    private val failed = HashMap<String, Long>()
    private val marking = HashSet<String>()
    private val busy = HashSet<String>()
    private val queue = ArrayDeque<String>()
    private var inspecting: String? = null
    private var token = 0
    private var latest: Map<String, GreetingCandidate> = emptyMap()
    private var seen: Set<String> = emptySet()

    val context: GreetingContext
        get() = GreetingContext(
            decided = decided.toSet(),
            friends = friends,
            friendsFailed = friendsFailed,
            failed = failed.keys.toSet(),
            marking = marking.toSet(),
            disabled = isDisabled()
        )

    fun onSnapshot(candidates: List<GreetingCandidate>) {
        val ids = candidates.mapTo(HashSet()) { it.conversationId }
        val gone = seen - ids
        seen = ids
        if (gone.isNotEmpty()) {
            failed.keys.removeAll(gone)
            marking.removeAll(gone)
        }
        candidates.forEach { c ->
            if (c.marked) marking.remove(c.conversationId)
            val failedAt = failed[c.conversationId]
            if (failedAt != null && failedAt != c.stamp) failed.remove(c.conversationId)
        }
        latest = candidates.associateBy { it.conversationId }
        loadFriendsIfNeeded()
        run()
    }

    fun onFriendsChanged(ids: Set<String>) {
        if (friends == null || friends == ids) return
        friends = ids
        run()
    }

    fun noteReplied(conversationId: String) {
        if (conversationId.isEmpty()) return
        failed.remove(conversationId)
        if (decided.add(conversationId)) persist()
        run()
    }

    private fun persist() = store.save(decided.toSet())

    private fun loadFriendsIfNeeded() {
        if (friends != null || friendsLoading || friendsRetryPending) return
        friendsLoading = true
        ports.loadFriends { ids ->
            friendsLoading = false
            if (ids != null) {
                friends = ids
                friendsFailed = false
                friendsRetryDelay = FRIENDS_RETRY_FIRST_MS
            } else {
                friendsFailed = true
                friendsRetryPending = true
                val delay = friendsRetryDelay
                friendsRetryDelay = (delay * 2).coerceAtMost(FRIENDS_RETRY_MAX_MS)
                schedule(delay) {
                    friendsRetryPending = false
                    loadFriendsIfNeeded()
                }
            }
            run()
        }
    }

    private fun run() {
        val plan = DemoConversationGroups.plan(latest.values, context, busy)
        if (plan.decide.isNotEmpty() && decided.addAll(plan.decide)) persist()
        plan.unmark.chunked(BATCH).forEach(::unmark)
        plan.inspect.forEach {
            busy += it
            queue += it
        }
        onChange(context)
        pump()
    }

    private fun unmark(ids: List<String>) {
        busy += ids
        ports.setGreeting(ids, false) {
            busy -= ids.toSet()
            onChange(context)
        }
    }

    private fun pump() {
        if (inspecting != null) return
        val id = queue.removeFirstOrNull() ?: return
        inspecting = id
        val mine = ++token
        schedule(INSPECT_TIMEOUT_MS) { if (token == mine) finish(id, null) }
        ports.inspect(id) { verdict -> if (token == mine) finish(id, verdict) }
    }

    private fun finish(id: String, verdict: Boolean?) {
        token++
        inspecting = null
        val c = latest[id]
        when {
            c == null -> busy -= id
            verdict == null -> {
                busy -= id
                failed[id] = c.stamp
            }
            verdict -> {
                busy -= id
                if (decided.add(id)) persist()
            }
            DemoConversationGroups.slot(c, context) != ConversationSlot.PENDING -> busy -= id
            else -> ports.setGreeting(listOf(id), true) { result ->
                busy -= id
                if (result.ok) {
                    if (latest[id]?.marked != true) marking += id
                } else {
                    failed[id] = latest[id]?.stamp ?: c.stamp
                }
                run()
            }
        }
        run()
    }

    companion object {
        const val BATCH = 100
        const val INSPECT_TIMEOUT_MS = 15_000L
        const val FRIENDS_RETRY_FIRST_MS = 2_000L
        const val FRIENDS_RETRY_MAX_MS = 30_000L
    }
}

class PrefsDecidedStore(context: Context, account: String) : DecidedStore {
    private val prefs = context.applicationContext.getSharedPreferences("demo_greeting_routes", Context.MODE_PRIVATE)
    private val key = "recent:$account"

    override fun load(): Set<String> = prefs.getStringSet(key, emptySet()).orEmpty().toSet()

    override fun save(ids: Set<String>) {
        prefs.edit().putStringSet(key, HashSet(ids)).apply()
    }
}

class SdkGreetingPorts(private val marks: ConversationListStore) : GreetingPorts {
    private val main = Handler(Looper.getMainLooper())

    override fun inspect(conversationId: String, done: (Boolean?) -> Unit) {
        val history = MessageListStore.create(conversationId)
        fun finish(verdict: Boolean?) {
            main.post { done(verdict) }
        }
        fun replied() = DemoConversationGroups.hasReply(
            history.state.messageList.value.map(DemoConversationClassifier::kindOf)
        )
        fun next(page: Int) {
            when {
                replied() -> finish(true)
                !history.state.hasOlderMessages.value || page >= MAX_PAGES -> finish(false)
                else -> history.loadOlderMessages(completion("inspectOlder") { ok -> if (ok) next(page + 1) else finish(null) })
            }
        }
        history.loadMessages(MessageLoadOption(pageCount = PAGE), completion("inspect") { ok ->
            if (ok) next(1) else finish(null)
        })
    }

    override fun setGreeting(ids: List<String>, greeting: Boolean, done: (GroupOpResult) -> Unit) {
        val operation = if (greeting) "markGreeting" else "unmarkGreeting"
        marks.markConversation(ids, DemoConversationClassifier.GREETING_MARK, greeting, object : CompletionHandler {
            override fun onSuccess() {
                main.post { done(GroupOpResult.OK) }
            }

            override fun onFailure(code: Int, desc: String) {
                val result = GroupOpResult.failed(code, desc)
                DemoGroupDiagnostics.record(operation, result)
                main.post { done(result) }
            }
        })
    }

    override fun loadFriends(done: (Set<String>?) -> Unit) {
        val contacts = ContactStore.shared
        contacts.loadFriends(completion("loadFriends") { ok ->
            main.post { done(if (ok) contacts.state.friendList.value.mapTo(HashSet()) { it.userID } else null) }
        })
    }

    private fun completion(operation: String, done: (Boolean) -> Unit) = object : CompletionHandler {
        override fun onSuccess() = done(true)

        override fun onFailure(code: Int, desc: String) {
            DemoGroupDiagnostics.record(operation, GroupOpResult.failed(code, desc))
            done(false)
        }
    }

    private companion object {
        const val PAGE = 20
        const val MAX_PAGES = 3
    }
}

data class GreetingView(
    val conversations: List<ConversationInfo> = emptyList(),
    val context: GreetingContext = GreetingContext()
)

object DemoGroupWatcher {
    private const val SETTLE_MS = 300L

    private var account: String? = null
    private var scope: CoroutineScope? = null
    private var watch: DemoGroupWatch? = null
    private var conversations: List<ConversationInfo> = emptyList()
    private val _state = MutableStateFlow(GreetingView())

    val state: StateFlow<GreetingView> = _state.asStateFlow()

    @OptIn(FlowPreview::class)
    fun ensureStarted(context: Context, accountId: String) {
        if (scope != null && account == accountId) return
        stop()
        account = accountId
        val main = Handler(Looper.getMainLooper())
        val store = ConversationListStore.create()
        var created: DemoGroupWatch? = null
        val current = DemoGroupWatch(
            SdkGreetingPorts(store),
            PrefsDecidedStore(context, accountId),
            schedule = { delay, action -> main.postDelayed(action, delay) },
            onChange = { ctx -> if (watch === created) publish(ctx) }
        )
        created = current
        watch = current
        publish(current.context)
        val running = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        scope = running
        PagedConversationLoader(SdkPagedConversations(store)).load()
        running.launch {
            store.state.conversationList.collect { list ->
                conversations = list
                publish(current.context)
            }
        }
        running.launch {
            store.state.conversationList.debounce(SETTLE_MS).collect { list ->
                current.onSnapshot(list.map { it.toGreetingCandidate() })
            }
        }
        running.launch {
            ContactStore.shared.state.friendList.collect { list ->
                current.onFriendsChanged(list.mapTo(HashSet()) { it.userID })
            }
        }
        running.launch {
            DemoGroupDiagnostics.changes.collect { publish(current.context) }
        }
    }

    fun noteReplied(conversationId: String) {
        watch?.noteReplied(conversationId)
    }

    fun slotOf(info: ConversationInfo, context: GreetingContext = _state.value.context): ConversationSlot =
        DemoConversationGroups.slot(info.toGreetingCandidate(), context)

    fun greetingMembers(view: GreetingView = _state.value): List<ConversationInfo> =
        view.conversations
            .filter { slotOf(it, view.context) == ConversationSlot.GREETING }
            .distinctBy { it.conversationID }

    fun stop() {
        scope?.cancel()
        scope = null
        account = null
        watch = null
        conversations = emptyList()
        _state.value = GreetingView()
    }

    private fun publish(context: GreetingContext) {
        _state.value = GreetingView(conversations, context)
    }
}

data class GroupOpResult(val ok: Boolean, val code: Int = 0, val desc: String = "") {
    companion object {
        val OK = GroupOpResult(true)
        fun failed(code: Int, desc: String) = GroupOpResult(false, code, desc)
    }
}

object DemoGroupDiagnostics {
    val PACKAGE_UNSUPPORTED_CODES = setOf(7013, 51013)

    @Volatile
    var logger: (String) -> Unit = { Log.w("Chat1v1Groups", it) }

    @Volatile
    var lastFailure: GroupOpResult? = null
        private set

    @Volatile
    var packageUnsupported: Boolean = false
        private set

    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 4)

    val changes: SharedFlow<Unit> = _changes.asSharedFlow()

    fun record(operation: String, result: GroupOpResult) {
        if (result.ok) return
        lastFailure = result
        if (result.code in PACKAGE_UNSUPPORTED_CODES && !packageUnsupported) {
            packageUnsupported = true
            _changes.tryEmit(Unit)
        }
        logger("$operation failed: code=${result.code} desc=${result.desc}")
        HostDiagnostics.record("group.$operation", result.code, result.desc)
    }

    fun emptyHint(default: String): String =
        if (packageUnsupported) DemoText.get(R.string.demo_the_current_sdkappid_plan_does_not_support) else default

    fun reset() {
        lastFailure = null
        packageUnsupported = false
    }
}

object DemoCallPromoter {
    private const val EVENT_START_CALL = "call.startCall"
    private const val KEY_PARTICIPANT_IDS = "participantIds"
    private const val KEY_CHAT_GROUP_ID = "chatGroupId"
    private const val C2C_PREFIX = "c2c_"

    private var subscribed = false

    private val observer = object : TUIObserver() {
        override fun onNotify(event: String, key: String?, params: NotifyParams?) {
            if (event == EVENT_START_CALL) promote(params?.data)
        }
    }

    fun ensureStarted() {
        if (subscribed) return
        subscribed = true
        TUIEventBus.shared.subscribe(EVENT_START_CALL, null, observer)
    }

    fun stop() {
        if (!subscribed) return
        subscribed = false
        TUIEventBus.shared.unsubscribe(EVENT_START_CALL, null, observer)
    }

    private fun promote(data: Map<String, Any?>?) {
        if (data == null) return
        val groupId = data[KEY_CHAT_GROUP_ID] as? String
        if (!groupId.isNullOrEmpty()) return
        val participants = (data[KEY_PARTICIPANT_IDS] as? List<*>).orEmpty().filterIsInstance<String>()
        if (participants.size != 1) return
        val peer = participants.first().takeIf { it.isNotBlank() } ?: return
        DemoGroupWatcher.noteReplied(C2C_PREFIX + peer)
    }
}
