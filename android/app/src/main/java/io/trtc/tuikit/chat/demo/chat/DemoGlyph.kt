package io.trtc.tuikit.chat.demo.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import io.trtc.tuikit.chat.hostbase.DemoUi

/**
 * Small stroke glyphs for the chat chrome (back, call, more, warning, close).
 * Drawn on Canvas so the demo carries no extra image assets.
 */
class DemoGlyph(context: Context, private val type: Type, color: String = DemoUi.TEXT) : View(context) {
    enum class Type { BACK, PHONE, MORE, WARNING, CLOSE }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        this.color = Color.parseColor(color)
        strokeWidth = resources.displayMetrics.density * 1.8f
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        this.color = Color.parseColor(color)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val cx = w / 2
        val cy = h / 2
        // Line glyphs sit at ~20dp inside a 40–52dp touch target; the warning fills its box.
        val s = minOf(w, h) * if (type == Type.WARNING) 0.42f else 0.21f
        when (type) {
            Type.BACK -> canvas.drawPath(Path().apply {
                moveTo(cx + s * 0.35f, cy - s)
                lineTo(cx - s * 0.45f, cy)
                lineTo(cx + s * 0.35f, cy + s)
            }, paint)
            Type.MORE -> {
                val r = paint.strokeWidth * 0.9f
                for (dy in listOf(-s * 0.8f, 0f, s * 0.8f)) canvas.drawCircle(cx, cy + dy, r, fill)
            }
            Type.PHONE -> canvas.drawPath(Path().apply {
                // Handset outline: top-left earpiece curving to bottom-right mouthpiece.
                moveTo(cx - s * 0.9f, cy - s * 0.55f)
                cubicTo(cx - s * 0.9f, cy - s * 0.95f, cx - s * 0.55f, cy - s, cx - s * 0.35f, cy - s * 0.7f)
                lineTo(cx - s * 0.15f, cy - s * 0.3f)
                lineTo(cx - s * 0.4f, cy - s * 0.05f)
                cubicTo(cx - s * 0.2f, cy + s * 0.35f, cx + s * 0.05f, cy + s * 0.55f, cx + s * 0.3f, cy + s * 0.6f)
                lineTo(cx + s * 0.55f, cy + s * 0.35f)
                lineTo(cx + s * 0.95f, cy + s * 0.6f)
                cubicTo(cx + s * 1.05f, cy + s * 0.85f, cx + s * 0.85f, cy + s * 1.05f, cx + s * 0.55f, cy + s)
                cubicTo(cx - s * 0.2f, cy + s * 0.9f, cx - s * 0.9f, cy + s * 0.2f, cx - s * 0.9f, cy - s * 0.55f)
                close()
            }, paint)
            Type.WARNING -> {
                canvas.drawPath(Path().apply {
                    moveTo(cx, cy - s)
                    lineTo(cx + s * 1.05f, cy + s * 0.85f)
                    lineTo(cx - s * 1.05f, cy + s * 0.85f)
                    close()
                }, fill)
                val mark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = DemoUi.tokens.toastColorWarning
                    strokeWidth = paint.strokeWidth
                    strokeCap = Paint.Cap.ROUND
                }
                canvas.drawLine(cx, cy - s * 0.35f, cx, cy + s * 0.25f, mark)
                canvas.drawCircle(cx, cy + s * 0.55f, mark.strokeWidth * 0.6f, mark.apply { style = Paint.Style.FILL })
            }
            Type.CLOSE -> {
                val k = s * 0.7f
                canvas.drawLine(cx - k, cy - k, cx + k, cy + k, paint)
                canvas.drawLine(cx + k, cy - k, cx - k, cy + k, paint)
            }
        }
    }

}
