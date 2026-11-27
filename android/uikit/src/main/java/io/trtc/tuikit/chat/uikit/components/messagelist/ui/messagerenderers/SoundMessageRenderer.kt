package io.trtc.tuikit.chat.uikit.components.messagelist.ui.messagerenderers
import android.content.Context
import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.TypedValue
import android.view.animation.LinearInterpolator
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.common.RtlUtils
import io.trtc.tuikit.chat.uikit.components.config.MessageAlignment
import io.trtc.tuikit.chat.uikit.components.messagelist.config.MessageListConfigProtocol
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.MessageRenderer
import io.trtc.tuikit.chat.uikit.components.messagelist.ui.RecyclableMessageRenderer
import io.trtc.tuikit.chat.uikit.components.messagelist.viewmodel.MessageListViewModel
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.atomicxcore.api.message.AudioMessagePayload
import io.trtc.tuikit.atomicxcore.api.message.MessageInfo
import io.trtc.tuikit.atomicxcore.api.message.MessageStatus

/**
 * Voice bubble per design S3/S8 (prototype `.bubble--voice`): 40dp high, width 140..200dp from the
 * duration (`140 + (dur - 6) * 5`), 12dp side padding, play glyph 14 + wave (2dp bars, 16dp max) + duration 12sp.
 * Bubble fill, tap-to-play and playback state still come from the SDK; this only draws the content.
 */
class SoundMessageRenderer : MessageRenderer, RecyclableMessageRenderer {
    companion object {
        private const val TAG_VOICE = "sound_voice"
        private const val MIN_WIDTH_DP = 140
        private const val MAX_WIDTH_DP = 200
        private const val HEIGHT_DP = 40

        private val WAVE_12 = intArrayOf(4, 10, 14, 6, 16, 12, 7, 15, 9, 13, 5, 8)
        private val WAVE_13 = intArrayOf(5, 9, 13, 7, 16, 11, 6, 12, 8, 14, 7, 10, 5)

        internal fun widthDp(durationSeconds: Int): Int =
            (MIN_WIDTH_DP + (durationSeconds - 6) * 5).coerceIn(MIN_WIDTH_DP, MAX_WIDTH_DP)

        internal fun barCount(widthDp: Int): Int = 12 + Math.round((widthDp - MIN_WIDTH_DP) / 10f)

        internal fun barHeightsDp(count: Int): IntArray {
            val sequence = if (count == 12) WAVE_12 else WAVE_13
            return IntArray(count) { sequence[it % sequence.size] }
        }

        internal fun formatDuration(seconds: Int): String = "${seconds.coerceAtLeast(0)}\u2033"
    }

    override fun createView(context: Context, parent: ViewGroup): View {
        val voice = VoiceBubbleContent(context)
        voice.tag = TAG_VOICE
        voice.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        return voice
    }

    override fun bindView(
        view: View,
        message: MessageInfo,
        viewModel: MessageListViewModel,
        config: MessageListConfigProtocol,
        colors: ColorTokens,
    ) {
        val voice = view as VoiceBubbleContent
        val payload = message.messagePayload as? AudioMessagePayload
        val duration = (payload?.audioDuration ?: 0).coerceAtLeast(0)
        val audioState = viewModel.audioPlayingState.value
        val isPlaying = audioState.playingMessageId == message.msgID && audioState.isPlaying

        voice.bind(
            durationSeconds = duration,
            isSelf = message.isSentBySelf,
            colors = colors,
            playing = isPlaying,
        )

        if (message.status == MessageStatus.VIOLATION) {
            view.setOnClickListener(null)
            view.isClickable = false
        } else {
            view.isClickable = true
            view.setOnClickListener { viewModel.playAudioMessage(message) }
        }
    }

    override fun onViewRecycled(view: View) {
        (view as? VoiceBubbleContent)?.stopProgress()
    }

    /** Play glyph + wave + duration in one row; the wave view paints played/unplayed bars. */
    class VoiceBubbleContent(context: Context) : LinearLayout(context) {
        private val density = context.resources.displayMetrics.density
        private val playView = PlayGlyphView(context)
        private val waveView = WaveView(context)
        private val durationView = TextView(context)
        private var progressAnimator: ValueAnimator? = null
        private var boundKey: String? = null

        init {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            minimumHeight = dp(HEIGHT_DP)
            setPadding(dp(12), 0, dp(12), 0)
            addView(playView, LayoutParams(dp(14), dp(14)))
            addView(waveView, LayoutParams(0, dp(16), 1f).apply { marginStart = dp(8); marginEnd = dp(8) })
            durationView.apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                maxLines = 1
                includeFontPadding = false
            }
            addView(durationView, LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }

        private fun dp(value: Int) = (value * density).toInt()

        fun bind(durationSeconds: Int, isSelf: Boolean, colors: ColorTokens, playing: Boolean) {
            val widthDp = widthDp(durationSeconds)
            val count = barCount(widthDp)
            val bars = barHeightsDp(count)
            val key = "$durationSeconds|$isSelf|$count"
            layoutParams = (layoutParams ?: LayoutParams(0, 0)).apply {
                width = dp(widthDp)
                height = ViewGroup.LayoutParams.WRAP_CONTENT
            }

            val idleBar: Int
            val unplayedBar: Int
            val playedBar: Int
            val playColor: Int
            val durationColor: Int
            if (isSelf) {
                idleBar = ColorUtils.setAlphaComponent(colors.textColorButton, (255 * 0.75f).toInt())
                unplayedBar = ColorUtils.setAlphaComponent(colors.textColorButton, (255 * 0.40f).toInt())
                playedBar = colors.textColorButton
                playColor = colors.textColorButton
                durationColor = idleBar
            } else {
                idleBar = ColorUtils.setAlphaComponent(colors.textColorPrimary, (255 * 0.82f).toInt())
                unplayedBar = colors.textColorTertiary
                playedBar = colors.textColorLink
                playColor = colors.textColorPrimary
                durationColor = colors.textColorSecondary
            }
            playView.color = playColor
            durationView.text = formatDuration(durationSeconds)
            durationView.setTextColor(durationColor)
            waveView.configure(bars.map { it * density }.toFloatArray(), idleBar, unplayedBar, playedBar, density)

            if (playing) {
                if (boundKey != key || progressAnimator?.isRunning != true) startProgress(durationSeconds)
            } else {
                stopProgress()
                waveView.setProgress(-1f)
            }
            boundKey = key
        }

        private fun startProgress(durationSeconds: Int) {
            progressAnimator?.cancel()
            progressAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = (durationSeconds.coerceAtLeast(1) * 1000L)
                interpolator = LinearInterpolator()
                addUpdateListener { waveView.setProgress(it.animatedValue as Float) }
                start()
            }
        }

        fun stopProgress() {
            progressAnimator?.cancel()
            progressAnimator = null
        }

        override fun onDetachedFromWindow() {
            stopProgress()
            super.onDetachedFromWindow()
        }
    }

    /** `progress < 0` paints every bar in the idle colour; otherwise bars up to progress are "played". */
    private class WaveView(context: Context) : View(context) {
        private var heights = FloatArray(0)
        private var idle = 0
        private var unplayed = 0
        private var played = 0
        private var progress = -1f
        private var barWidth = 2f
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()

        fun configure(heightsPx: FloatArray, idleColor: Int, unplayedColor: Int, playedColor: Int, density: Float) {
            heights = heightsPx
            idle = idleColor
            unplayed = unplayedColor
            played = playedColor
            barWidth = 2f * density
            invalidate()
        }

        fun setProgress(value: Float) {
            progress = value
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val count = heights.size
            if (count == 0) return
            val gap = if (count > 1) (width - barWidth * count) / (count - 1) else 0f
            val playedBars = if (progress < 0f) -1 else Math.round(progress * count)
            for (i in 0 until count) {
                paint.color = when {
                    playedBars < 0 -> idle
                    i < playedBars -> played
                    else -> unplayed
                }
                val left = i * (barWidth + gap)
                val top = (height - heights[i]) / 2f
                rect.set(left, top, left + barWidth, top + heights[i])
                canvas.drawRoundRect(rect, barWidth / 2f, barWidth / 2f, paint)
            }
        }
    }
}
