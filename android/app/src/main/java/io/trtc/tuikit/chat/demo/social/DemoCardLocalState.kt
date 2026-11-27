package io.trtc.tuikit.chat.demo.social

object DemoCardLocalState {
    enum class Burn { SEALED, VIEWING, EXPIRED }

    enum class Swap { INVITED, READY, REVEALED }

    data class BurnView(val state: Burn, val remainingMs: Long)

    data class ListenView(val joined: Boolean, val playing: Boolean, val positionMs: Long)

    const val DEFAULT_BURN_SECONDS = 5
    const val MAX_BURN_SECONDS = 30
    const val SWAP_REVEAL_DELAY_MS = 500L

    private class Listen(var playing: Boolean, var offsetMs: Long, var startedAt: Long)

    private val burnDeadlines = HashMap<String, Long>()
    private val swaps = HashMap<String, Swap>()
    private val swapReadyAt = HashMap<String, Long>()
    private val openedRedPackets = HashSet<String>()
    private val listens = HashMap<String, Listen>()

    fun burnSeconds(raw: String?): Int =
        (raw?.toIntOrNull() ?: DEFAULT_BURN_SECONDS).coerceIn(1, MAX_BURN_SECONDS)

    @Synchronized
    fun burn(instanceId: String, nowMs: Long): BurnView {
        val deadline = burnDeadlines[instanceId] ?: return BurnView(Burn.SEALED, 0L)
        val remaining = deadline - nowMs
        return if (remaining > 0) BurnView(Burn.VIEWING, remaining) else BurnView(Burn.EXPIRED, 0L)
    }

    @Synchronized
    fun openBurn(instanceId: String, seconds: Int, nowMs: Long): Boolean {
        if (instanceId.isBlank() || burnDeadlines.containsKey(instanceId)) return false
        burnDeadlines[instanceId] = nowMs + seconds.coerceIn(1, MAX_BURN_SECONDS) * 1000L
        return true
    }

    private fun swapLocked(instanceId: String, nowMs: Long): Swap {
        val current = swaps[instanceId] ?: Swap.INVITED
        val readyAt = swapReadyAt[instanceId]
        if (current == Swap.READY && readyAt != null && nowMs - readyAt >= SWAP_REVEAL_DELAY_MS) {
            swaps[instanceId] = Swap.REVEALED
            return Swap.REVEALED
        }
        return current
    }

    @Synchronized
    fun swap(instanceId: String, nowMs: Long): Swap = swapLocked(instanceId, nowMs)

    @Synchronized
    fun swapRevealRemainingMs(instanceId: String, nowMs: Long): Long {
        val readyAt = swapReadyAt[instanceId] ?: return 0L
        if (swapLocked(instanceId, nowMs) != Swap.READY) return 0L
        return (readyAt + SWAP_REVEAL_DELAY_MS - nowMs).coerceAtLeast(0L)
    }

    @Synchronized
    fun pickSwap(instanceId: String, nowMs: Long): Swap {
        if (instanceId.isBlank()) return Swap.INVITED
        val current = swapLocked(instanceId, nowMs)
        if (current != Swap.INVITED) return current
        swaps[instanceId] = Swap.READY
        swapReadyAt[instanceId] = nowMs
        return Swap.READY
    }

    @Synchronized
    fun redPacketOpened(instanceId: String): Boolean = instanceId in openedRedPackets

    @Synchronized
    fun openRedPacket(instanceId: String): Boolean = instanceId.isNotBlank() && openedRedPackets.add(instanceId)

    @Synchronized
    fun listen(instanceId: String, durationMs: Long, nowMs: Long): ListenView {
        val item = listens[instanceId] ?: return ListenView(false, false, 0L)
        val raw = item.offsetMs + if (item.playing) nowMs - item.startedAt else 0L
        val position = if (durationMs > 0) raw.coerceIn(0L, durationMs) else raw.coerceAtLeast(0L)
        return ListenView(true, item.playing && (durationMs <= 0 || position < durationMs), position)
    }

    @Synchronized
    fun toggleListen(instanceId: String, durationMs: Long, nowMs: Long): ListenView {
        if (instanceId.isBlank()) return ListenView(false, false, 0L)
        val current = listen(instanceId, durationMs, nowMs)
        val item = listens[instanceId]
        if (item == null) {
            listens[instanceId] = Listen(true, 0L, nowMs)
        } else {
            item.offsetMs = current.positionMs
            item.playing = !current.playing
            item.startedAt = nowMs
        }
        return listen(instanceId, durationMs, nowMs)
    }

    @Synchronized
    fun reset() {
        burnDeadlines.clear()
        swaps.clear()
        swapReadyAt.clear()
        openedRedPackets.clear()
        listens.clear()
    }
}
