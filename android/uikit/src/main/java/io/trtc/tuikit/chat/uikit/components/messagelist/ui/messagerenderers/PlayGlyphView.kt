package io.trtc.tuikit.chat.uikit.components.messagelist.ui.messagerenderers

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View

/** Prototype icons.js `play` (M8.6 5.4 l10 6.6 -10 6.6 z in a 24 viewBox), scaled to the view width. */
internal class PlayGlyphView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0xFFFFFFFF.toInt()
    }
    private val path = Path()

    var color: Int = 0xFFFFFFFF.toInt()
        set(value) {
            field = value
            paint.color = value
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        val scale = width / 24f
        path.reset()
        path.moveTo(8.6f * scale, 5.4f * scale)
        path.lineTo(18.6f * scale, 12f * scale)
        path.lineTo(8.6f * scale, 18.6f * scale)
        path.close()
        canvas.drawPath(path, paint)
    }
}
