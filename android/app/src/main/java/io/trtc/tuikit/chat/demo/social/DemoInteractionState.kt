package io.trtc.tuikit.chat.demo.social

/**
 * Client-side interaction state for `chat.card` / `chat.event` (spec 03 §4).
 *
 * Everything here is local, in-memory demo state: there is no business backend, ledger or
 * server revision. Events are merged with these rules:
 *  - the same `eventId` is applied at most once (retries and re-delivery are harmless);
 *  - per (instance, SDK sender) the `actorSequence` only moves forward, an older one never
 *    rolls state back (it is a local counter, not a global revision);
 *  - actions are declarative (`select optionId`), never "toggle on every receipt".
 */
class DemoInteractionState {
    enum class Outcome { APPLIED, DUPLICATE, STALE, INVALID }

    data class Event(
        val targetInstanceId: String,
        val eventId: String,
        /** The real SDK sender, never a name claimed inside the payload. */
        val senderId: String,
        val actorSequence: Int,
        val kind: String,
        val action: String,
        val params: Map<String, String>
    )

    private val seenEvents = LinkedHashSet<String>()
    private val lastSequence = HashMap<String, Int>()
    private val selections = HashMap<String, MutableMap<String, String>>()

    @Synchronized
    fun apply(event: Event): Outcome {
        if (event.targetInstanceId.isBlank() || event.eventId.isBlank() || event.senderId.isBlank()) {
            return Outcome.INVALID
        }
        if (event.action !in DemoCardProtocol.EVENT_ACTIONS[event.kind].orEmpty()) return Outcome.INVALID
        val optionId = event.params["optionId"]
        if (event.action == "select" && optionId.isNullOrBlank()) return Outcome.INVALID

        if (event.eventId in seenEvents) return Outcome.DUPLICATE
        remember(event.eventId)

        val key = "${event.targetInstanceId}|${event.senderId}"
        if (event.actorSequence <= (lastSequence[key] ?: 0)) return Outcome.STALE
        lastSequence[key] = event.actorSequence

        if (event.action == "select" && optionId != null) {
            selections.getOrPut(event.targetInstanceId) { HashMap() }[event.senderId] = optionId
        }
        return Outcome.APPLIED
    }

    @Synchronized
    fun selection(instanceId: String, senderId: String): String? = selections[instanceId]?.get(senderId)

    /** Next local sequence for [senderId] on [instanceId]; strictly greater than any applied one. */
    @Synchronized
    fun nextSequence(instanceId: String, senderId: String): Int = (lastSequence["$instanceId|$senderId"] ?: 0) + 1

    private fun remember(eventId: String) {
        seenEvents.add(eventId)
        if (seenEvents.size > MAX_REMEMBERED_EVENTS) seenEvents.remove(seenEvents.first())
    }

    companion object {
        /**
         * Actor used for choices made on this device. Real peer events (when a synced transport
         * is verified) must use the SDK sender id instead of this constant.
         */
        const val LOCAL_ACTOR = "local"
        const val MAX_REMEMBERED_EVENTS = 512
    }
}

/** One state per conversation; demo state is isolated per conversation and lost on process exit. */
object DemoInteractionStore {
    private val states = HashMap<String, DemoInteractionState>()

    @Synchronized
    fun state(conversationId: String): DemoInteractionState = states.getOrPut(conversationId) { DemoInteractionState() }

    @Synchronized
    fun clear() = states.clear()
}

/**
 * Decides whether a card effect (pat wobble, dice roll, gift pulse) may play (spec 03 §4.4).
 * History paging and cell recycling re-bind old cards: only a card whose message is fresh
 * and whose `eventId` has not played yet animates, once.
 */
object DemoEffectGate {
    /** Message age that still counts as "just arrived". Server time skew beyond this suppresses the effect. */
    const val REALTIME_WINDOW_MS = 10_000L
    private const val MAX_REMEMBERED = 256
    private val played = LinkedHashSet<String>()

    @Synchronized
    fun shouldPlay(eventId: String, messageTimeMs: Long, nowMs: Long = System.currentTimeMillis()): Boolean {
        if (eventId.isBlank()) return false
        if (nowMs - messageTimeMs > REALTIME_WINDOW_MS) return false
        if (!played.add(eventId)) return false
        if (played.size > MAX_REMEMBERED) played.remove(played.first())
        return true
    }

    @Synchronized
    fun reset() = played.clear()
}
