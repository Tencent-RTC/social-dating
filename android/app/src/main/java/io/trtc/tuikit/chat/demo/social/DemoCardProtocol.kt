package io.trtc.tuikit.chat.demo.social

import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.hostbase.DemoText
import java.util.UUID
import org.json.JSONObject
import kotlin.random.Random

/**
 * Demo interaction card protocol (`businessID = chat.card`, spec 03 §3).
 *
 * Card content (pat text, track title, swap sample) is local fake data; the message
 * that carries it is a real IM CUSTOM message sent through MessageInputStore. There is
 * no business backend, order, ledger or server lease. The call message format is never
 * touched: `call` is deliberately not an allowed kind.
 */
object DemoCardProtocol {
    const val BUSINESS_ID = "chat1v1.card"
    const val VERSION = 1
    const val DATA_SOURCE = "demo_mock"

    /** Whitelist: unknown kinds render a compatibility hint instead of executing anything. */
    val ALLOWED_KINDS = setOf("pat", "listen", "photoSwap", "location", "burn", "dice", "rps", "quiz", "gift", "redpacket")

    /** Guard against oversized or hostile payloads (spec 03: limit size and depth). */
    const val MAX_BYTES = 4096

    data class Card(
        val kind: String,
        val version: Int,
        val instanceId: String,
        val eventId: String,
        val actorSequence: Int,
        val payload: Map<String, String>
    ) {
        val isKnownKind: Boolean get() = kind in ALLOWED_KINDS
    }

    /**
     * Builds the customData JSON. [instanceId]/[eventId] are stable per user action so a
     * network retry of the same action never creates a second interaction.
     */
    fun build(
        kind: String,
        payload: Map<String, Any>,
        instanceId: String = UUID.randomUUID().toString(),
        eventId: String = UUID.randomUUID().toString(),
        actorSequence: Int = 1
    ): String {
        require(kind in ALLOWED_KINDS) { "Unsupported demo card kind: $kind" }
        val json = JSONObject()
            .put("businessID", BUSINESS_ID)
            .put("version", VERSION)
            .put("kind", kind)
            .put("dataSource", DATA_SOURCE)
            .put("instanceId", instanceId)
            .put("eventId", eventId)
            .put("actorSequence", actorSequence)
            .put("payload", JSONObject(payload))
        val text = json.toString()
        require(text.toByteArray().size <= MAX_BYTES) { "Demo card payload too large" }
        return text
    }

    /**
     * Control events (`businessID = chat.event`). Only declared kind/action pairs exist and
     * `call` is not among them. Sending is deliberately NOT wired: whether online-only custom
     * messages stay out of unread counts, summaries and push is unverified on the locked SDK
     * (spec 03 §4.5/§4.6), so choices stay local-only demos until that is measured.
     */
    const val EVENT_BUSINESS_ID = "chat1v1.event"
    val EVENT_ACTIONS: Map<String, Set<String>> = mapOf("quiz" to setOf("select"))

    fun buildEvent(
        kind: String,
        targetInstanceId: String,
        action: String,
        params: Map<String, Any>,
        eventId: String = UUID.randomUUID().toString(),
        actorSequence: Int = 1
    ): String {
        require(action in EVENT_ACTIONS[kind].orEmpty()) { "Unsupported demo event: $kind/$action" }
        require(targetInstanceId.isNotBlank()) { "Demo event needs targetInstanceId" }
        val text = JSONObject()
            .put("businessID", EVENT_BUSINESS_ID)
            .put("version", VERSION)
            .put("kind", kind)
            .put("dataSource", DATA_SOURCE)
            .put("targetInstanceId", targetInstanceId)
            .put("eventId", eventId)
            .put("actorSequence", actorSequence)
            .put("payload", JSONObject(params).put("action", action))
            .toString()
        require(text.toByteArray().size <= MAX_BYTES) { "Demo event payload too large" }
        return text
    }

    /** [senderId] must be the real SDK sender of the message, not anything from the payload. */
    fun parseEvent(customData: String?, senderId: String): DemoInteractionState.Event? {
        if (customData.isNullOrBlank() || customData.toByteArray().size > MAX_BYTES) return null
        val json = runCatching { JSONObject(customData) }.getOrNull() ?: return null
        if (json.optString("businessID") != EVENT_BUSINESS_ID) return null
        if (json.optString("dataSource") != DATA_SOURCE) return null
        if (json.optInt("version", 0) <= 0) return null
        val target = json.optString("targetInstanceId")
        if (target.isBlank()) return null
        val payloadJson = json.optJSONObject("payload") ?: return null
        val params = buildMap {
            payloadJson.keys().forEach { key ->
                val value = payloadJson.opt(key)
                if (value is String || value is Number || value is Boolean) put(key, value.toString())
            }
        }
        val kind = json.optString("kind")
        val action = params["action"] ?: return null
        if (action !in EVENT_ACTIONS[kind].orEmpty()) return null
        return DemoInteractionState.Event(
            targetInstanceId = target,
            eventId = json.optString("eventId"),
            senderId = senderId,
            actorSequence = json.optInt("actorSequence", 0),
            kind = kind,
            action = action,
            params = params - "action"
        )
    }

    /** Returns null for anything that is not a well-formed chat.card message. */
    fun parse(customData: String?): Card? {
        if (customData.isNullOrBlank() || customData.toByteArray().size > MAX_BYTES) return null
        val json = runCatching { JSONObject(customData) }.getOrNull() ?: return null
        if (json.optString("businessID") != BUSINESS_ID) return null
        if (json.optString("dataSource") != DATA_SOURCE) return null
        val version = json.optInt("version", 0)
        if (version <= 0) return null
        val payloadJson = json.optJSONObject("payload") ?: JSONObject()
        val payload = buildMap {
            payloadJson.keys().forEach { key ->
                // Flat string view only; nested objects are ignored (depth limit).
                val value = payloadJson.opt(key)
                if (value is String || value is Number || value is Boolean) put(key, value.toString())
            }
        }
        return Card(
            kind = json.optString("kind"),
            version = version,
            instanceId = json.optString("instanceId"),
            eventId = json.optString("eventId"),
            actorSequence = json.optInt("actorSequence", 0),
            payload = payload
        )
    }

    /** Conversation-list / push summary; never claims real business state. */
    fun summary(card: Card?): String = if (card == null) DemoText.get(R.string.demo_message) else summaryOf(card.kind)

    fun summaryOf(kind: String): String = when (kind) {
        "pat" -> DemoText.get(R.string.demo_pat)
        "listen" -> DemoText.get(R.string.demo_listen_together_2)
        "photoSwap" -> DemoText.get(R.string.demo_photo_swap)
        "location" -> DemoText.get(R.string.demo_location)
        "burn" -> DemoText.get(R.string.demo_burn_after_reading)
        "dice" -> DemoText.get(R.string.demo_dice)
        "rps" -> DemoText.get(R.string.demo_rock_paper_scissors)
        "quiz" -> DemoText.get(R.string.demo_crush_quiz)
        "gift" -> DemoText.get(R.string.demo_gift)
        "redpacket" -> DemoText.get(R.string.demo_red_packet)
        else -> DemoText.get(R.string.demo_interaction_card)
    }
}

/**
 * Values that are decided once, by the sender, at send time (spec 03 section 6).
 * Receivers render what the payload carries and never roll again, so both ends show one result.
 */
object DemoCardRolls {
    fun rolled(kind: String, payload: Map<String, Any>, random: Random = Random.Default): Map<String, Any> = when (kind) {
        "dice" -> payload + ("value" to random.nextInt(1, 7))
        "rps" -> payload + DemoRps.roll(random)
        else -> payload
    }
}

/**
 * Content of the rock-paper-scissors card (`kind = rps`, spec 03 section 6).
 *
 * The sender rolls the hand and a sample outcome once and carries both in the payload, exactly
 * like the dice value, so neither end ever re-rolls. The outcome is local sample text and not
 * a rules engine: the receiver has not thrown yet, so only the sender's card words it, and the
 * receiver is invited to play again.
 */
object DemoRps {
    const val ROCK = "rock"
    const val SCISSORS = "scissors"
    const val PAPER = "paper"
    const val WIN = "win"
    const val DRAW = "draw"
    const val LOSE = "lose"

    val HANDS = listOf(ROCK, SCISSORS, PAPER)
    val OUTCOMES = listOf(WIN, DRAW, LOSE)

    fun roll(random: Random = Random.Default): Map<String, Any> = mapOf(
        "hand" to HANDS[random.nextInt(HANDS.size)],
        "outcome" to OUTCOMES[random.nextInt(OUTCOMES.size)]
    )

    fun handLabel(hand: String?): String = when (hand) {
        SCISSORS -> DemoText.get(R.string.demo_scissors)
        PAPER -> DemoText.get(R.string.demo_paper)
        else -> DemoText.get(R.string.demo_rock)
    }

    fun handDrawable(hand: String?): Int = when (hand) {
        SCISSORS -> R.drawable.demo_rps_scissors
        PAPER -> R.drawable.demo_rps_paper
        else -> R.drawable.demo_rps_rock
    }
}
