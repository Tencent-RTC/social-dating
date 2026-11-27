package io.trtc.tuikit.chat.demo.chat

import android.app.Dialog
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.trtc.tuikit.chat.demo.R
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.R as BaseR

class CallChoiceDialog(
    context: Context,
    private val onVideo: () -> Unit,
    private val onAudio: () -> Unit
) : Dialog(context) {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
            setGravity(Gravity.BOTTOM)
            addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(0.45f)
        }
        setContentView(build())
    }

    private fun build(): View {
        val t = DemoUi.tokens
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8) + navigationBarHeight())
        }
        val group = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = Host.rounded(context, t.bgColorDialog, 14f)
        }
        group.addView(row(DemoText.get(R.string.demo_video_call), t.textColorLink) { dismiss(); onVideo() })
        group.addView(View(context).apply { setBackgroundColor(t.strokeColorSecondary) }, LinearLayout.LayoutParams(-1, 1))
        group.addView(row(DemoText.get(R.string.demo_voice_call), t.textColorLink) { dismiss(); onAudio() })
        column.addView(group, LinearLayout.LayoutParams(-1, -2))
        column.addView(
            row(DemoText.get(BaseR.string.demo_cancel), t.textColorPrimary, bold = true) { dismiss() }.apply {
                background = Host.rounded(context, t.bgColorDialog, 14f)
            },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) }
        )
        return column
    }

    private fun row(label: String, color: Int, bold: Boolean = false, onClick: () -> Unit): FrameLayout =
        FrameLayout(context).apply {
            isClickable = true
            setOnClickListener { onClick() }
            addView(
                Host.text(context, label, 17f, color, bold = bold),
                FrameLayout.LayoutParams(-2, -2, Gravity.CENTER)
            )
            minimumHeight = dp(56)
            layoutParams = LinearLayout.LayoutParams(-1, dp(56))
        }

    private fun dp(value: Int) = DemoUi.dp(context, value)

    private fun navigationBarHeight(): Int {
        val id = context.resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (id > 0) context.resources.getDimensionPixelSize(id) else 0
    }
}
