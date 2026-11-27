package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import com.tencent.qcloud.tuikit.tuicallkit.R
import io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Bottom block of the S9 (voice) / S10 (video) call page:
 *
 *   voice : 音效 | 送礼 | 话题 · 麦克风 | 挂断 | 扬声器   (the topic card is a draggable overlay of CallSkinLayer)
 *   video : tip pill · 音效 | 美颜 | 送礼 | 话题 | 虚化 · 麦克风 | 摄像头 | 挂断 | 扬声器 | 翻转
 *
 * The control row is the original TUICallKit capability (microphone / camera / audio route / flip /
 * hang up / background blur) bound through [CallSkinController]; the function row is the demo's
 * local entertainment layer ([CallSkinHub]).
 */
class SocialCallControls(
    context: Context,
    private val controller: CallSkinController,
    private val hub: CallSkinHub
) : LinearLayout(context) {
    private val t = CallSkin.tokens(context)
    private val video = controller.isVideo
    private var job: Job? = null
    private var hangingUp = false
    private var blurOn = false

    private lateinit var mic: FrameLayout
    private lateinit var micLabel: TextView
    private var camera: FrameLayout? = null
    private var cameraLabel: TextView? = null
    private lateinit var speaker: FrameLayout
    private lateinit var speakerLabel: TextView
    private lateinit var hang: FrameLayout
    private var blur: FrameLayout? = null
    private val ctrlItems = mutableListOf<View>()

    init {
        orientation = VERTICAL
        gravity = Gravity.BOTTOM
        clipChildren = false
        clipToPadding = false
        val side = CallSkin.dp(context, 20f)
        setPadding(side, 0, side, CallSkin.dp(context, 16f))
        val tip = tipPill()
        addView(tip, centered(CallSkin.dp(context, 12f)).apply { height = CallSkin.dp(context, 26f) })
        tip.postDelayed({
            if (!tip.isAttachedToWindow) return@postDelayed
            tip.animate().cancel()
            tip.animate().alpha(0f).setDuration(200)
                .withEndAction { if (tip.alpha == 0f) tip.visibility = View.INVISIBLE }
                .start()
        }, TIP_VISIBLE_MS)
        addView(functionRow(), rowParams(0))
        addView(controlRow(), rowParams(CallSkin.dp(context, 18f)))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        job = CoroutineScope(Dispatchers.Main).apply {
            launch { controller.micOn.collect { on -> renderMic(on) } }
            launch { controller.speakerOn.collect { on -> renderSpeaker(on) } }
            if (video) launch { controller.cameraOn.collect { on -> renderCamera(on) } }
        }.coroutineContext[Job]
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        job?.cancel()
    }

    // ---- blocks ----------------------------------------------------------------------------

    private fun tipPill(): View {
        val pill = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = CallSkin.rounded(context, t.bgColorTagMask, 13f)
            setPadding(CallSkin.dp(context, 10f), 0, CallSkin.dp(context, 12f), 0)
        }
        pill.addView(CallSkin.icon(context, R.drawable.callskin_ic_shield, 14f, t.textColorWarning))
        val tip = if (video) R.string.callskin_tip_video else R.string.callskin_tip_voice
        val label = CallSkin.text(context, context.getString(tip), 12f, t.textColorSecondary)
        pill.addView(label, LayoutParams(-2, -2).apply { marginStart = CallSkin.dp(context, 6f) })
        pill.layoutParams = LayoutParams(-2, CallSkin.dp(context, 26f))
        return pill
    }

    private fun functionRow(): View {
        val row = spreadRow(Gravity.BOTTOM)
        val small = if (video) 52f else 64f
        val left = mutableListOf<View>()
        left += funItem(R.drawable.callskin_ic_sfx, 26f, R.string.callskin_fun_sfx, small) {
            hub.openPanel(CallEffectsPanel.Kind.Sound)
        }
        if (video) left += funItem(R.drawable.callskin_ic_beauty, 26f, R.string.callskin_fun_beauty, small) {
            hub.openPanel(CallEffectsPanel.Kind.Beauty)
        }
        val gift = giftItem(if (video) 60f else 64f)
        val right = mutableListOf<View>()
        right += funItem(R.drawable.callskin_ic_topic, 24f, R.string.callskin_fun_topic, small) {
            hub.toggleTopic()
        }
        if (video && controller.blurAvailable) right += funItem(R.drawable.callskin_ic_blur, 26f, R.string.callskin_fun_blur, small) {
            blurOn = !blurOn
            blur?.let { CallSkin.applyCircleState(it, R.drawable.callskin_ic_blur, 26f, t, blurOn) }
            controller.toggleBlur()
        }.also { column -> blur = column.getChildAt(0) as FrameLayout }
        distributeAroundCenter(row, left, gift, right)
        return row
    }

    private fun controlRow(): View {
        val row = spreadRow(Gravity.TOP)
        val size = if (video) 52f else 60f
        val width = if (video) 52f else 64f
        val items = mutableListOf<View>()

        val micColumn = ctrlColumn(width, size, R.drawable.callskin_ic_mic, 26f, topPad = if (video) 4f else 0f, gap = if (video) 12f else 8f) { controller.toggleMic() }
        mic = micColumn.getChildAt(0) as FrameLayout; micLabel = micColumn.getChildAt(1) as TextView
        items += micColumn

        if (video) {
            val cam = ctrlColumn(width, size, R.drawable.callskin_ic_cam, 26f, topPad = 4f, gap = 12f) { controller.toggleCamera() }
            camera = cam.getChildAt(0) as FrameLayout; cameraLabel = cam.getChildAt(1) as TextView
            items += cam
        }

        val hangSize = 60f
        val hangColumn = LinearLayout(context).apply { orientation = VERTICAL; gravity = Gravity.CENTER_HORIZONTAL }
        hang = FrameLayout(context).apply {
            layoutParams = LayoutParams(CallSkin.dp(context, hangSize), CallSkin.dp(context, hangSize))
            background = CallSkin.oval(t.buttonColorHangupDefault)
            addView(CallSkin.icon(context, R.drawable.callskin_ic_hangup, 30f, Color.WHITE).apply {
                layoutParams = FrameLayout.LayoutParams(CallSkin.dp(context, 30f), CallSkin.dp(context, 30f), Gravity.CENTER)
            })
        }
        hangColumn.addView(hang)
        hangColumn.addView(
            CallSkin.text(context, context.getString(R.string.callview_text_hangup), 12f, t.textColorPrimary),
            LayoutParams(-2, -2).apply { topMargin = CallSkin.dp(context, 8f) }
        )
        hangColumn.layoutParams = LayoutParams(CallSkin.dp(context, if (video) 60f else 64f), -2)
        CallSkin.pressable(hangColumn) { hangUp() }
        items += hangColumn

        val spk = ctrlColumn(width, size, R.drawable.callskin_ic_speaker, 26f, topPad = if (video) 4f else 0f, gap = if (video) 12f else 8f) { controller.toggleSpeaker() }
        speaker = spk.getChildAt(0) as FrameLayout; speakerLabel = spk.getChildAt(1) as TextView
        items += spk

        if (video) {
            val flip = ctrlColumn(width, size, R.drawable.callskin_ic_flip, 26f, topPad = 4f, gap = 12f) { controller.flipCamera() }
            (flip.getChildAt(1) as TextView).text = context.getString(R.string.callskin_ctrl_flip)
            CallSkin.applyCircleState(flip.getChildAt(0) as FrameLayout, R.drawable.callskin_ic_flip, 26f, t, false)
            items += flip
        }
        ctrlItems += items
        distribute(row, items)
        return row
    }

    // ---- builders --------------------------------------------------------------------------

    private fun spreadRow(gravity: Int) = LinearLayout(context).apply {
        orientation = HORIZONTAL
        this.gravity = gravity
        clipChildren = false
    }

    /** `justify-content: space-between`: items with a weight-1 spacer between each pair. */
    private fun distribute(row: LinearLayout, items: List<View>) {
        items.forEachIndexed { index, view ->
            if (index > 0) row.addView(Space(context), LayoutParams(0, 1, 1f))
            row.addView(view)
        }
    }

    /**
     * The gift button is always the centre of the row, whatever the number of buttons on either side: the left and
     * right groups each take half of the remaining width (weight 1) and spread their buttons inside it, so with two
     * buttons per side the result equals `space-between`, and with 1 / 2 or 2 / 1 the gift still does not move.
     */
    private fun distributeAroundCenter(row: LinearLayout, left: List<View>, gift: View, right: List<View>) {
        val leftGroup = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.BOTTOM; clipChildren = false }
        left.forEach { view ->
            leftGroup.addView(view)
            leftGroup.addView(Space(context), LayoutParams(0, 1, 1f))
        }
        val rightGroup = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.BOTTOM; clipChildren = false }
        right.forEach { view ->
            rightGroup.addView(Space(context), LayoutParams(0, 1, 1f))
            rightGroup.addView(view)
        }
        row.addView(leftGroup, LayoutParams(0, -2, 1f))
        row.addView(gift)
        row.addView(rightGroup, LayoutParams(0, -2, 1f))
    }

    private fun funItem(@DrawableRes icon: Int, glyph: Float, @StringRes label: Int, width: Float, onClick: () -> Unit): LinearLayout {
        val column = LinearLayout(context).apply {
            orientation = VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LayoutParams(CallSkin.dp(context, width), -2)
        }
        column.addView(CallSkin.circleButton(context, 48f, icon, glyph, t, false))
        column.addView(
            CallSkin.text(context, context.getString(label), 12f, t.textColorPrimary),
            LayoutParams(-2, -2).apply { topMargin = CallSkin.dp(context, 6f) }
        )
        CallSkin.pressable(column, 0.88f, onClick)
        return column
    }

    private fun giftItem(width: Float): LinearLayout {
        val column = LinearLayout(context).apply {
            orientation = VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LayoutParams(CallSkin.dp(context, width), -2)
        }
        val base = FrameLayout(context).apply {
            layoutParams = LayoutParams(CallSkin.dp(context, 56f), CallSkin.dp(context, 56f))
            background = CallSkin.giftBase(context, t)
            CallSkin.brandGlow(this, t)
            addView(CallSkin.icon(context, R.drawable.callskin_ic_gift, 34f).apply {
                layoutParams = FrameLayout.LayoutParams(CallSkin.dp(context, 34f), CallSkin.dp(context, 34f), Gravity.CENTER)
            })
        }
        column.addView(base)
        column.addView(
            CallSkin.text(context, context.getString(R.string.callskin_fun_gift), 12f, t.textColorPrimary, bold = true),
            LayoutParams(-2, -2).apply { topMargin = CallSkin.dp(context, 6f) }
        )
        CallSkin.pressable(column, 0.88f) {
            hub.sendGift { AtomicToast.show(context, context.getString(R.string.callskin_gift_failed)) }
        }
        return column
    }

    private fun ctrlColumn(width: Float, size: Float, @DrawableRes icon: Int, glyph: Float, topPad: Float, gap: Float, onClick: () -> Unit): LinearLayout {
        val column = LinearLayout(context).apply {
            orientation = VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            layoutParams = LayoutParams(CallSkin.dp(context, width), -2)
            setPadding(0, CallSkin.dp(context, topPad), 0, 0)
            clipToPadding = false
            clipChildren = false
        }
        column.addView(CallSkin.circleButton(context, size, icon, glyph, t, false))
        // Labels may be wider than the 52dp column (design: `white-space: nowrap`), so the label view
        // is 28dp wider than the column and pulled back with negative side margins.
        column.addView(
            CallSkin.text(context, "", 12f, t.textColorPrimary).apply { gravity = Gravity.CENTER },
            LayoutParams(CallSkin.dp(context, width + 28f), -2).apply {
                topMargin = CallSkin.dp(context, gap)
                marginStart = -CallSkin.dp(context, 14f)
                marginEnd = -CallSkin.dp(context, 14f)
            }
        )
        CallSkin.pressable(column) { if (!hangingUp) onClick() }
        return column
    }

    private fun centered(bottomMargin: Int) = LayoutParams(-2, -2).apply {
        gravity = Gravity.CENTER_HORIZONTAL
        this.bottomMargin = bottomMargin
    }

    private fun rowParams(top: Int) = LayoutParams(-1, -2).apply { topMargin = top }

    // ---- state -----------------------------------------------------------------------------

    private fun renderMic(on: Boolean) {
        CallSkin.applyCircleState(mic, if (on) R.drawable.callskin_ic_mic else R.drawable.callskin_ic_mic_off, 26f, t, on)
        micLabel.text = context.getString(
            when {
                video && on -> R.string.callskin_video_mic_on
                video -> R.string.callskin_video_mic_off
                on -> R.string.callview_toast_disable_mute
                else -> R.string.callview_toast_enable_mute
            }
        )
    }

    private fun renderSpeaker(on: Boolean) {
        CallSkin.applyCircleState(speaker, if (on) R.drawable.callskin_ic_speaker else R.drawable.callskin_ic_speaker_off, 26f, t, on)
        speakerLabel.text = context.getString(if (on) R.string.callview_text_speaker else R.string.callview_text_use_earpiece)
    }

    private fun renderCamera(on: Boolean) {
        val box = camera ?: return
        CallSkin.applyCircleState(box, if (on) R.drawable.callskin_ic_cam else R.drawable.callskin_ic_cam_off, 26f, t, on)
        cameraLabel?.text = context.getString(if (on) R.string.callskin_video_cam_on else R.string.callskin_video_cam_off)
    }

    private fun hangUp() {
        if (hangingUp) return
        hangingUp = true
        ctrlItems.filter { it !== hang.parent }.forEach { it.alpha = 0.8f }
        controller.hangup()
    }

    private companion object {
        const val TIP_VISIBLE_MS = 5000L
    }
}
