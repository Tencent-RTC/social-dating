package com.tencent.qcloud.tuikit.tuicallkit.view.callview.skin

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import androidx.annotation.StringRes
import com.tencent.cloud.tuikit.engine.call.TUICallEngine
import com.tencent.liteav.audio.TXAudioEffectManager.TXVoiceChangerType
import com.tencent.liteav.audio.TXAudioEffectManager.TXVoiceReverbType
import com.tencent.qcloud.tuikit.tuicallkit.R

/**
 * What the call page can change on the live stream: the voice changer, the reverb and the three basic beauty levels.
 * They go straight to TRTC, so the peer hears / sees the result, and every change is written to the preferences,
 * so the next call starts from the same voice and picture.
 */
object CallEffectsState {
    private const val FILE = "tuicallkit_call_effects"
    private const val KEY_VOICE = "voice"
    private const val KEY_REVERB = "reverb"
    private const val KEY_BEAUTY = "beauty"
    private const val KEY_WHITENESS = "whiteness"
    private const val KEY_RUDDY = "ruddy"

    var voice = 0
    var reverb = 0
    var beauty = 0
    var whiteness = 0
    var ruddy = 0

    private var prefs: SharedPreferences? = null

    /** Reads the saved levels once per process, the first time a call page opens. */
    fun load(context: Context) {
        if (prefs != null) return
        val store = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        prefs = store
        voice = store.getInt(KEY_VOICE, 0)
        reverb = store.getInt(KEY_REVERB, 0)
        beauty = store.getInt(KEY_BEAUTY, 0)
        whiteness = store.getInt(KEY_WHITENESS, 0)
        ruddy = store.getInt(KEY_RUDDY, 0)
    }

    fun save() {
        val editor = prefs?.edit() ?: return
        editor.putInt(KEY_VOICE, voice)
        editor.putInt(KEY_REVERB, reverb)
        editor.putInt(KEY_BEAUTY, beauty)
        editor.putInt(KEY_WHITENESS, whiteness)
        editor.putInt(KEY_RUDDY, ruddy)
        editor.apply()
    }

    /** Pushes the saved levels to the live stream when the call page opens. */
    fun applyTo(engine: CallEffectsEngine) {
        engine.setVoiceChanger(voice)
        engine.setReverb(reverb)
        engine.setBeauty(beauty)
        engine.setWhiteness(whiteness)
        engine.setRuddy(ruddy)
    }
}

/** Engine calls behind [CallEffectsPanel]; the debug preview swaps in a no-op. */
interface CallEffectsEngine {
    fun setVoiceChanger(index: Int)
    fun setReverb(index: Int)
    fun setBeauty(level: Int)
    fun setWhiteness(level: Int)
    fun setRuddy(level: Int)
}

class TrtcCallEffectsEngine(private val context: Context) : CallEffectsEngine {
    private val trtc get() = TUICallEngine.createInstance(context).trtcCloudInstance

    override fun setVoiceChanger(index: Int) {
        val type = TXVoiceChangerType.values().getOrNull(index) ?: TXVoiceChangerType.TXLiveVoiceChangerType_0
        trtc.audioEffectManager.setVoiceChangerType(type)
    }

    override fun setReverb(index: Int) {
        val type = TXVoiceReverbType.values().getOrNull(index) ?: TXVoiceReverbType.TXLiveVoiceReverbType_0
        trtc.audioEffectManager.setVoiceReverbType(type)
    }

    override fun setBeauty(level: Int) {
        trtc.beautyManager.setBeautyStyle(com.tencent.liteav.beauty.TXBeautyManager.TXBeautyStyleSmooth)
        trtc.beautyManager.setBeautyLevel(level.toFloat())
    }

    override fun setWhiteness(level: Int) = trtc.beautyManager.setWhitenessLevel(level.toFloat())

    override fun setRuddy(level: Int) = trtc.beautyManager.setRuddyLevel(level.toFloat())
}

object NoopCallEffectsEngine : CallEffectsEngine {
    override fun setVoiceChanger(index: Int) {}
    override fun setReverb(index: Int) {}
    override fun setBeauty(level: Int) {}
    override fun setWhiteness(level: Int) {}
    override fun setRuddy(level: Int) {}
}

/**
 * Bottom sheet of the call page, drawn in the call skin (dark tokens, brand colour for the selection).
 * [Kind.Sound] = voice changer + reverb chips, [Kind.Beauty] = three 0-9 sliders. It lives inside the call view, so it
 * disappears with the call and needs no dialog window.
 */
class CallEffectsPanel(
    context: Context,
    private val kind: Kind,
    private val engine: CallEffectsEngine,
    private val onClose: () -> Unit
) : FrameLayout(context) {
    enum class Kind { Sound, Beauty }

    private val t = CallSkin.tokens(context)

    private val voiceLabels = intArrayOf(
        R.string.callskin_voice_0, R.string.callskin_voice_1, R.string.callskin_voice_2, R.string.callskin_voice_3,
        R.string.callskin_voice_4, R.string.callskin_voice_5, R.string.callskin_voice_6, R.string.callskin_voice_7
    )
    private val reverbLabels = intArrayOf(
        R.string.callskin_reverb_0, R.string.callskin_reverb_1, R.string.callskin_reverb_2, R.string.callskin_reverb_3,
        R.string.callskin_reverb_4, R.string.callskin_reverb_5, R.string.callskin_reverb_6, R.string.callskin_reverb_7
    )

    init {
        isClickable = true // the dimmed area closes the panel and keeps the touch away from the call page below
        setBackgroundColor(Color.argb(90, 0, 0, 0))
        setOnClickListener { onClose() }
        val sheet = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            background = CallSkin.rounded(context, CallSkin.withAlpha(t.bgColorOperate, 0.96f), 20f)
            setPadding(CallSkin.dp(context, 16f), CallSkin.dp(context, 14f), CallSkin.dp(context, 16f), CallSkin.dp(context, 24f))
        }
        sheet.addView(header())
        if (kind == Kind.Sound) {
            sheet.addView(section(R.string.callskin_voice_title))
            sheet.addView(chips(voiceLabels, CallEffectsState.voice) { index ->
                CallEffectsState.voice = index
                CallEffectsState.save()
                engine.setVoiceChanger(index)
            })
            sheet.addView(section(R.string.callskin_reverb_title))
            sheet.addView(chips(reverbLabels, CallEffectsState.reverb) { index ->
                CallEffectsState.reverb = index
                CallEffectsState.save()
                engine.setReverb(index)
            })
        } else {
            sheet.addView(slider(R.string.callskin_beauty_smooth, CallEffectsState.beauty) {
                CallEffectsState.beauty = it; CallEffectsState.save(); engine.setBeauty(it)
            })
            sheet.addView(slider(R.string.callskin_beauty_whiten, CallEffectsState.whiteness) {
                CallEffectsState.whiteness = it; CallEffectsState.save(); engine.setWhiteness(it)
            })
            sheet.addView(slider(R.string.callskin_beauty_ruddy, CallEffectsState.ruddy) {
                CallEffectsState.ruddy = it; CallEffectsState.save(); engine.setRuddy(it)
            })
        }
        addView(sheet, LayoutParams(-1, -2, Gravity.BOTTOM))
    }

    private fun header(): View {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val title = if (kind == Kind.Sound) R.string.callskin_fun_sfx else R.string.callskin_fun_beauty
        row.addView(CallSkin.text(context, context.getString(title), 16f, t.textColorPrimary, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(CallSkin.text(context, context.getString(R.string.callskin_panel_done), 14f, t.textColorLink).apply {
            setPadding(CallSkin.dp(context, 12f), CallSkin.dp(context, 6f), 0, CallSkin.dp(context, 6f))
            setOnClickListener { onClose() }
        })
        return row
    }

    private fun section(@StringRes title: Int) = CallSkin.text(context, context.getString(title), 12f, t.textColorSecondary).apply {
        layoutParams = LinearLayout.LayoutParams(-2, -2).apply { topMargin = CallSkin.dp(context, 16f); bottomMargin = CallSkin.dp(context, 8f) }
    }

    /** One horizontally scrolling row of single-choice chips; the selected one carries the brand colour. */
    private fun chips(labels: IntArray, selected: Int, onPick: (Int) -> Unit): View {
        val row = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        val views = ArrayList<TextView>()
        fun paint(current: Int) = views.forEachIndexed { index, view ->
            val on = index == current
            view.background = if (on) CallSkin.brandGradient(t, CallSkin.dp(context, 16f).toFloat(), android.graphics.drawable.GradientDrawable.Orientation.LEFT_RIGHT)
            else CallSkin.rounded(context, CallSkin.withAlpha(Color.WHITE, 0.10f), 16f)
            view.setTextColor(if (on) t.textColorButton else t.textColorPrimary)
        }
        labels.forEachIndexed { index, label ->
            val chip = CallSkin.text(context, context.getString(label), 13f, t.textColorPrimary).apply {
                gravity = Gravity.CENTER
                setPadding(CallSkin.dp(context, 14f), 0, CallSkin.dp(context, 14f), 0)
                setOnClickListener { paint(index); onPick(index) }
            }
            views += chip
            row.addView(chip, LinearLayout.LayoutParams(-2, CallSkin.dp(context, 32f)).apply { marginEnd = CallSkin.dp(context, 8f) })
        }
        paint(selected)
        return HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = OVER_SCROLL_NEVER
            addView(row, ViewGroup.LayoutParams(-2, -2))
        }
    }

    /** 0-9 level slider with the current value on the right (TRTC takes 0-9). */
    private fun slider(@StringRes label: Int, value: Int, onChange: (Int) -> Unit): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(-1, -2).apply { topMargin = CallSkin.dp(context, 14f) }
        }
        row.addView(CallSkin.text(context, context.getString(label), 14f, t.textColorPrimary), LinearLayout.LayoutParams(CallSkin.dp(context, 56f), -2))
        val number = CallSkin.text(context, value.toString(), 14f, t.textColorSecondary).apply { gravity = Gravity.END }
        val bar = SeekBar(context).apply {
            max = 9
            progress = value
            progressTintList = android.content.res.ColorStateList.valueOf(t.buttonColorPrimaryDefault)
            thumbTintList = android.content.res.ColorStateList.valueOf(t.buttonColorPrimaryDefault)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                    number.text = progress.toString()
                    if (fromUser) onChange(progress)
                }

                override fun onStartTrackingTouch(seekBar: SeekBar) {}
                override fun onStopTrackingTouch(seekBar: SeekBar) {}
            })
        }
        row.addView(bar, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(number, LinearLayout.LayoutParams(CallSkin.dp(context, 28f), -2))
        return row
    }
}
