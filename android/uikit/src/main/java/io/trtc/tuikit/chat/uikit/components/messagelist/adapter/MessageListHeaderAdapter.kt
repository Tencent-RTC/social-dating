package io.trtc.tuikit.chat.uikit.components.messagelist.adapter

import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView

/**
 * One optional item that sits before the earliest message of a conversation (the list is reverse-laid-out, so it is the
 * last adapter position and shows at the visual top). It is not a message: the host supplies the view, it never counts
 * as unread, never reaches the conversation summary and has no long-press menu.
 *
 * It is chained behind [MessageListAdapter] with a `ConcatAdapter`, so message positions are untouched.
 */
internal class MessageListHeaderAdapter : RecyclerView.Adapter<MessageListHeaderAdapter.HeaderHolder>() {

    private var content: View? = null
    private var visible = false
    private var heightPx = ViewGroup.LayoutParams.WRAP_CONTENT

    class HeaderHolder(val container: FrameLayout) : RecyclerView.ViewHolder(container)

    val hasContent: Boolean get() = content != null

    override fun getItemCount(): Int = if (visible && content != null) 1 else 0

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): HeaderHolder {
        val container = FrameLayout(parent.context)
        container.layoutParams = RecyclerView.LayoutParams(RecyclerView.LayoutParams.MATCH_PARENT, heightPx)
        return HeaderHolder(container)
    }

    override fun onBindViewHolder(holder: HeaderHolder, position: Int) {
        val view = content ?: return
        if (view.parent !== holder.container) {
            (view.parent as? ViewGroup)?.removeView(view)
            holder.container.removeAllViews()
            holder.container.addView(view, FrameLayout.LayoutParams(-1, -1))
        }
        holder.container.layoutParams = RecyclerView.LayoutParams(RecyclerView.LayoutParams.MATCH_PARENT, heightPx)
    }

    override fun onViewRecycled(holder: HeaderHolder) {
        holder.container.removeAllViews()
    }

    fun setContent(view: View?) {
        val wasShown = itemCount > 0
        content = view
        if (wasShown) {
            notifyItemRemoved(0)
        }
        if (itemCount > 0) {
            notifyItemInserted(0)
        }
    }

    fun setVisible(value: Boolean) {
        if (visible == value) {
            return
        }
        val before = itemCount
        visible = value
        val after = itemCount
        when {
            before == 0 && after == 1 -> notifyItemInserted(0)
            before == 1 && after == 0 -> notifyItemRemoved(0)
        }
    }

    fun setHeight(px: Int) {
        if (heightPx == px) {
            return
        }
        heightPx = px
        if (itemCount > 0) {
            notifyItemChanged(0)
        }
    }
}
