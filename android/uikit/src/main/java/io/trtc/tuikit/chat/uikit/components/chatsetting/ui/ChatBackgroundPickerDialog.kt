package io.trtc.tuikit.chat.uikit.components.chatsetting.ui
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.provider.Settings
import android.view.animation.PathInterpolator
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.chat.uikit.components.chatsetting.background.ChatBackgroundPresetItem
import io.trtc.tuikit.chat.uikit.components.chatsetting.background.ChatBackgroundPresetProvider
import io.trtc.tuikit.chat.uikit.components.common.expandTouchTarget
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens

class ChatBackgroundPickerDialog(
    private val context: Context,
    private val selectedImageUri: String?,
    private val onBackgroundSelected: (String?) -> Unit
) {
    private val dialog = Dialog(context, android.R.style.Theme_Translucent_NoTitleBar)
    private val density = context.resources.displayMetrics.density
    private var overlayView: View? = null
    private var panelView: View? = null
    private var leaving = false

    fun show() {
        val colors = ThemeStore.shared(context).themeState.value.currentTheme.tokens.color
        dialog.setContentView(buildRootView(colors))
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.BOTTOM)
            clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        }
        dialog.setCanceledOnTouchOutside(true)
        // Back goes through the same slide-down as the close button.
        dialog.setOnKeyListener { _, keyCode, event ->
            if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                dismiss()
                true
            } else {
                keyCode == android.view.KeyEvent.KEYCODE_BACK
            }
        }
        dialog.show()
        playEnter()
    }

    private fun dismiss() {
        if (!dialog.isShowing || leaving) return
        leaving = true
        playExit { if (dialog.isShowing) dialog.dismiss() }
    }

    private fun animationsEnabled(): Boolean =
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) }
            .getOrDefault(1f) != 0f

    /** Dim fades in while the panel rises from the bottom edge. */
    private fun playEnter() {
        val overlay = overlayView ?: return
        val panel = panelView ?: return
        if (!animationsEnabled()) return
        overlay.alpha = 0f
        panel.visibility = View.INVISIBLE
        panel.post {
            panel.translationY = panel.height.toFloat()
            panel.visibility = View.VISIBLE
            overlay.animate().alpha(1f).setDuration(ENTER_MS).setInterpolator(EASE_OUT).start()
            panel.animate().translationY(0f).setDuration(ENTER_MS).setInterpolator(EASE_OUT).start()
        }
    }

    private fun playExit(end: () -> Unit) {
        val overlay = overlayView
        val panel = panelView
        if (overlay == null || panel == null || !animationsEnabled()) return end()
        overlay.animate().alpha(0f).setDuration(EXIT_MS).setInterpolator(EASE_OUT).start()
        panel.animate().translationY(panel.height.toFloat()).setDuration(EXIT_MS).setInterpolator(EASE_OUT)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) = end()
            }).start()
    }

    private fun buildRootView(colors: ColorTokens): View {
        val overlay = FrameLayout(context).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            setBackgroundColor(colors.bgColorMask)
            setOnClickListener { dismiss() }
        }

        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(dp(16f), dp(16f), dp(16f), dp(16f), 0f, 0f, 0f, 0f)
                setColor(colors.bgColorOperate)
            }
            isClickable = true
            isFocusable = true
        }
        panel.addView(buildHeader(colors))
        panel.addView(
            buildGrid(colors),
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)
        )

        overlay.addView(
            panel,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (context.resources.displayMetrics.heightPixels * 0.65f).toInt(),
                Gravity.BOTTOM
            )
        )
        overlayView = overlay
        panelView = panel
        return overlay
    }

    private fun buildHeader(colors: ColorTokens): View {
        val header = FrameLayout(context).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            setPadding(dp(16f).toInt(), dp(14f).toInt(), dp(16f).toInt(), dp(14f).toInt())
        }
        val titleView = TextView(context).apply {
            text = context.getString(R.string.chat_setting_select_chat_background)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(colors.textColorPrimary)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        header.addView(
            titleView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        val closeView = TextView(context).apply {
            text = "×"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setTextColor(colors.textColorSecondary)
            gravity = Gravity.CENTER
            setOnClickListener { dismiss() }
        }
        header.addView(
            closeView,
            FrameLayout.LayoutParams(
                dp(32f).toInt(),
                dp(32f).toInt(),
                Gravity.CENTER_VERTICAL or Gravity.END
            )
        )
        closeView.expandTouchTarget()
        return header
    }

    private fun buildGrid(colors: ColorTokens): View {
        return RecyclerView(context).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            layoutManager = GridLayoutManager(context, COLUMN_COUNT)
            adapter = ChatBackgroundAdapter(
                items = ChatBackgroundPresetProvider.getPresetItems(),
                selectedImageUri = selectedImageUri,
                colors = colors,
                onClick = { item ->
                    onBackgroundSelected(item.imageUri)
                    dismiss()
                }
            )
            val padding = dp(12f).toInt()
            setPadding(padding, padding, padding, padding)
            clipToPadding = false
            setBackgroundColor(colors.bgColorOperate)
        }
    }

    private fun dp(value: Float): Float = value * density

    /** Thumbnail cell shaped like the phone screen (9:19.5) so the full-screen presets show uncropped. */
    private class PhoneRatioFrameLayout(context: Context) : FrameLayout(context) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val width = MeasureSpec.getSize(widthMeasureSpec)
            super.onMeasure(
                widthMeasureSpec,
                MeasureSpec.makeMeasureSpec((width * 19.5f / 9f).toInt(), MeasureSpec.EXACTLY)
            )
        }
    }

    private class ChatBackgroundAdapter(
        private val items: List<ChatBackgroundPresetItem>,
        private val selectedImageUri: String?,
        private val colors: ColorTokens,
        private val onClick: (ChatBackgroundPresetItem) -> Unit
    ) : RecyclerView.Adapter<ChatBackgroundAdapter.ViewHolder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val density = parent.resources.displayMetrics.density
            val container = FrameLayout(parent.context).apply {
                val padding = (8f * density).toInt()
                setPadding(padding, padding, padding, padding)
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            }
            val preview = PhoneRatioFrameLayout(parent.context).apply {
                background = GradientDrawable().apply {
                    cornerRadius = 8f * density
                    setColor(this@ChatBackgroundAdapter.colors.bgColorTopBar)
                }
                clipToOutline = true
            }
            container.addView(
                preview,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER
                )
            )
            return ViewHolder(container, preview)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val item = items[position]
            holder.preview.removeAllViews()
            holder.preview.background = buildPreviewBackground(holder.preview.context, item)
            val selected = item.imageUri == selectedImageUri || (item.isDefault && selectedImageUri.isNullOrBlank())
            holder.preview.foreground = if (selected) buildSelectedBorder(holder.preview.context) else null
            if (item.isDefault) {
                holder.preview.addView(buildDefaultLabel(holder.preview.context))
            } else {
                val imageView = ImageView(holder.preview.context).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    layoutParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                }
                holder.preview.addView(imageView)
                Glide.with(holder.preview.context.applicationContext)
                    .load(item.thumbnailUri)
                    .centerCrop()
                    .into(imageView)
                if (item.nameRes != 0) holder.preview.addView(buildNameLabel(holder.preview.context, item.nameRes))
            }
            if (selected) holder.preview.addView(buildCheckBadge(holder.preview.context))
            holder.itemView.setOnClickListener { onClick(item) }
        }

        override fun getItemCount(): Int = items.size

        private fun buildPreviewBackground(context: Context, item: ChatBackgroundPresetItem): GradientDrawable {
            val density = context.resources.displayMetrics.density
            val selected = item.imageUri == selectedImageUri || (item.isDefault && selectedImageUri.isNullOrBlank())
            return GradientDrawable().apply {
                cornerRadius = 8f * density
                setColor(this@ChatBackgroundAdapter.colors.bgColorTopBar)
            }
        }

        private fun buildSelectedBorder(context: Context): GradientDrawable {
            val density = context.resources.displayMetrics.density
            return GradientDrawable().apply {
                cornerRadius = 8f * density
                setStroke((2f * density).toInt(), this@ChatBackgroundAdapter.colors.buttonColorPrimaryDefault)
            }
        }

        /** Preset name at the bottom of the thumbnail, on a soft black fade so it reads on light and dark images. */
        private fun buildNameLabel(context: Context, nameRes: Int): View {
            val density = context.resources.displayMetrics.density
            return TextView(context).apply {
                text = context.getString(nameRes)
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setShadowLayer(3f * density, 0f, density, 0x66000000)
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding((6f * density).toInt(), (18f * density).toInt(), (6f * density).toInt(), (8f * density).toInt())
                background = GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    intArrayOf(0x00000000, 0x80000000.toInt())
                )
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM
                )
            }
        }

        private fun buildCheckBadge(context: Context): View {
            val density = context.resources.displayMetrics.density
            val size = (20f * density).toInt()
            return TextView(context).apply {
                text = "\u2713"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(this@ChatBackgroundAdapter.colors.buttonColorPrimaryDefault)
                }
                layoutParams = FrameLayout.LayoutParams(size, size, Gravity.TOP or Gravity.END).apply {
                    setMargins(0, (6f * density).toInt(), (6f * density).toInt(), 0)
                }
            }
        }

        private fun buildDefaultLabel(context: Context): View {
            return TextView(context).apply {
                text = context.getString(R.string.chat_setting_chat_background_default)
                setTextColor(colors.textColorSecondary)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
        }

        class ViewHolder(
            itemView: View,
            val preview: FrameLayout
        ) : RecyclerView.ViewHolder(itemView)
    }

    private companion object {
        const val COLUMN_COUNT = 3
        const val ENTER_MS = 300L
        const val EXIT_MS = 220L
        val EASE_OUT = PathInterpolator(0.22f, 0.61f, 0.36f, 1f)
    }
}
