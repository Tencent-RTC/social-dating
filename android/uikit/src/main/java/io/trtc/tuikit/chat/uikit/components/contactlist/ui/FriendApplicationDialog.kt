package io.trtc.tuikit.chat.uikit.components.contactlist.ui
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import io.trtc.tuikit.chat.uikit.R
import io.trtc.tuikit.atomicx.common.util.ScreenUtil.dp2px
import io.trtc.tuikit.atomicx.widget.basicwidget.alertdialog.AtomicAlertDialog
import io.trtc.tuikit.atomicx.widget.basicwidget.alertdialog.cancelButton
import io.trtc.tuikit.atomicx.widget.basicwidget.alertdialog.confirmButton
import io.trtc.tuikit.chat.uikit.components.common.findViewModelStoreOwner
import io.trtc.tuikit.chat.uikit.components.common.displayName
import io.trtc.tuikit.chat.uikit.components.contactlist.viewmodel.FriendApplicationSubViewModel
import io.trtc.tuikit.chat.uikit.components.contactlist.viewmodel.FriendApplicationSubViewModelFactory
import io.trtc.tuikit.atomicx.theme.ThemeStore
import io.trtc.tuikit.atomicx.theme.tokens.ColorTokens
import io.trtc.tuikit.chat.uikit.components.widgets.Avatar
import io.trtc.tuikit.chat.uikit.components.widgets.Avatar.AvatarContent
import io.trtc.tuikit.atomicxcore.api.contact.ContactStore
import io.trtc.tuikit.atomicxcore.api.contact.FriendApplicationInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

internal class FriendApplicationDialog(
    context: Context,
    private val contactStore: ContactStore,
    private val peerTags: ((String) -> View?)? = null,
    private val peerFullTags: ((String) -> View?)? = null
) : ContactSubPageDialog(context) {

    private val viewModel: FriendApplicationSubViewModel by lazy {
        val owner = context.findViewModelStoreOwner()
            ?: error("FriendApplicationDialog requires a ViewModelStoreOwner host context.")
        val key = "${FriendApplicationSubViewModel::class.java.name}:${System.identityHashCode(this)}"
        ViewModelProvider(owner, FriendApplicationSubViewModelFactory(contactStore))
            .get(key, FriendApplicationSubViewModel::class.java)
    }
    private val acceptedState = FriendApplicationAcceptedState()
    private var liveApplications: List<FriendApplicationInfo> = emptyList()
    private var scope: CoroutineScope? = null
    private lateinit var recyclerView: RecyclerView
    private lateinit var emptyTextView: TextView
    private lateinit var adapter: FriendApplicationAdapter
    private lateinit var searchContainer: FrameLayout
    private lateinit var searchInner: LinearLayout
    private lateinit var searchIcon: ImageView
    private lateinit var searchHint: TextView
    private lateinit var addFriendIcon: ImageView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setTitle(context.getString(R.string.contact_list_new_contacts))

        val colors = getColors()
        val dm = context.resources.displayMetrics

        addFriendIcon = ImageView(context).apply {
            setImageResource(R.drawable.contact_list_ic_add_friend)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            contentDescription = context.getString(R.string.contact_list_add_friend)
            setOnClickListener { openAddFriend() }
        }
        addTrailingAction(addFriendIcon)

        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        column.addView(buildSearchEntry(dm))

        emptyTextView = TextView(context).apply {
            text = context.getString(R.string.contact_list_no_friend_application)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            gravity = Gravity.CENTER
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        }
        column.addView(emptyTextView)

        adapter = FriendApplicationAdapter(
            context = context,
            isAccepted = acceptedState::isAccepted,
            peerTags = peerTags,
            onItemClick = { application ->
                FriendApplicationDetailDialog(
                    context = context,
                    application = application,
                    fullTags = peerFullTags?.invoke(application.userID),
                    onAccept = { info, close -> accept(info, close) },
                    onRefuse = { info, close -> confirmRefuse(info, close) }
                ).show()
            },
            onAccept = { accept(it) },
            onRefuse = { confirmRefuse(it) }
        )

        recyclerView = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context)
            this.adapter = this@FriendApplicationDialog.adapter
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        }
        column.addView(recyclerView)
        contentContainer.addView(column)

        applyColors(colors)
    }

    override fun onStart() {
        super.onStart()
        val newScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        scope = newScope

        newScope.launch {
            viewModel.friendApplications.collectLatest { applications ->
                liveApplications = FriendApplicationRows.received(applications)
                renderList()
            }
        }

        newScope.launch {
            ThemeStore.shared(context).themeState.collectLatest {
                val colors = it.currentTheme.tokens.color
                refreshNavBarColors(colors)
                applyColors(colors)
                adapter.updateColors(colors)
            }
        }
    }

    override fun onStop() {
        super.onStop()
        scope?.cancel()
        scope = null
    }

    private fun buildSearchEntry(dm: android.util.DisplayMetrics): View {
        val side = dp2px(ContactSceneSpec.PAGE_PADDING_DP.toFloat(), dm).toInt()
        searchIcon = ImageView(context).apply {
            setImageResource(R.drawable.contact_list_ic_search)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        searchHint = TextView(context).apply {
            text = context.getString(R.string.contact_list_new_contacts_search_hint)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ContactSceneSpec.SEARCH_ENTRY_TEXT_SP.toFloat())
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        searchInner = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp2px(12f, dm).toInt(), 0, dp2px(12f, dm).toInt(), 0)
            addView(searchIcon, LinearLayout.LayoutParams(dp2px(16f, dm).toInt(), dp2px(16f, dm).toInt()).apply {
                marginEnd = dp2px(6f, dm).toInt()
            })
            addView(searchHint, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            contentDescription = context.getString(R.string.contact_list_new_contacts_search_hint)
            setOnClickListener { openAddFriend() }
        }
        searchContainer = FrameLayout(context).apply {
            setPadding(
                side,
                dp2px(ContactSceneSpec.SEARCH_ENTRY_PADDING_TOP_DP.toFloat(), dm).toInt(),
                side,
                dp2px(ContactSceneSpec.SEARCH_ENTRY_PADDING_BOTTOM_DP.toFloat(), dm).toInt()
            )
            addView(searchInner, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dp2px(ContactSceneSpec.SEARCH_ENTRY_HEIGHT_DP.toFloat(), dm).toInt()
            ))
        }
        return searchContainer
    }

    private fun applyColors(colors: ColorTokens) {
        val dm = context.resources.displayMetrics
        emptyTextView.setTextColor(colors.textColorSecondary)
        searchContainer.setBackgroundColor(colors.bgColorTopBar)
        searchInner.background = GradientDrawable().apply {
            cornerRadius = dp2px(ContactSceneSpec.SEARCH_ENTRY_RADIUS_DP.toFloat(), dm)
            setColor(colors.bgColorInput)
        }
        searchIcon.setColorFilter(colors.textColorSecondary)
        searchHint.setTextColor(colors.textColorTertiary)
        addFriendIcon.setColorFilter(colors.textColorPrimary)
    }

    /** Live applications plus the rows accepted during this visit (the SDK drops them on accept). */
    private fun renderList() {
        val rows = acceptedState.merge(liveApplications)
        if (rows.isEmpty()) {
            emptyTextView.visibility = View.VISIBLE
            recyclerView.visibility = View.GONE
        } else {
            emptyTextView.visibility = View.GONE
            recyclerView.visibility = View.VISIBLE
            adapter.submitList(rows)
        }
    }

    private fun openAddFriend() {
        ContactFlowLauncher.showAddFriendPage(context, contactStore)
    }

    private fun accept(application: FriendApplicationInfo, close: (() -> Unit)? = null) {
        viewModel.acceptFriendApplication(
            application = application,
            onSuccess = {
                acceptedState.markAccepted(application)
                renderList()
                close?.invoke()
            },
            onFailure = ::showFailureToast
        )
    }

    private fun confirmRefuse(application: FriendApplicationInfo, close: (() -> Unit)? = null) {
        AtomicAlertDialog(context).apply {
            init {
                content = context.getString(R.string.contact_list_refuse_confirm, application.displayName)
                confirmButton(context.getString(R.string.uikit_confirm)) { _ ->
                    viewModel.refuseFriendApplication(
                        application = application,
                        onSuccess = { close?.invoke() },
                        onFailure = ::showFailureToast
                    )
                }
                cancelButton(context.getString(R.string.uikit_cancel))
            }
            show()
        }
    }

    private fun showFailureToast(message: String) {
        if (message.isNotBlank()) {
            io.trtc.tuikit.atomicx.widget.basicwidget.toast.AtomicToast.show(context, message)
        }
    }
}

private class FriendApplicationAdapter(
    private val context: Context,
    private val isAccepted: (String) -> Boolean,
    private val peerTags: ((String) -> View?)? = null,
    private val onItemClick: (FriendApplicationInfo) -> Unit,
    private val onAccept: (FriendApplicationInfo) -> Unit,
    private val onRefuse: (FriendApplicationInfo) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private var items: List<FriendApplicationInfo> = emptyList()
    private var colors: ColorTokens = ThemeStore.shared(context).themeState.value.currentTheme.tokens.color

    fun submitList(newList: List<FriendApplicationInfo>) {
        items = newList
        notifyDataSetChanged()
    }

    fun refresh() {
        notifyDataSetChanged()
    }

    fun updateColors(newColors: ColorTokens) {
        colors = newColors
        notifyDataSetChanged()
    }

    override fun getItemViewType(position: Int): Int = if (position == 0) TYPE_HEADER else TYPE_ROW

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val dm = parent.resources.displayMetrics
        if (viewType == TYPE_HEADER) {
            val header = TextView(parent.context).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER_VERTICAL
                setPaddingRelative(dp2px(ContactSceneSpec.PAGE_PADDING_DP.toFloat(), dm).toInt(), 0, 0, 0)
                layoutParams = RecyclerView.LayoutParams(
                    RecyclerView.LayoutParams.MATCH_PARENT,
                    dp2px(ContactSceneSpec.SECTION_HEADER_HEIGHT_DP.toFloat(), dm).toInt()
                )
            }
            return HeaderHolder(header)
        }
        val rowHeight = dp2px(ContactSceneSpec.REQUEST_ROW_HEIGHT_DP.toFloat(), dm).toInt()
        val hPadStart = dp2px(16f, dm).toInt()
        val spacing = dp2px(12f, dm).toInt()

        val row = LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
            layoutParams = RecyclerView.LayoutParams(
                RecyclerView.LayoutParams.MATCH_PARENT,
                rowHeight
            )
            setPaddingRelative(hPadStart, 0, 0, 0)
        }

        val avatar = Avatar(parent.context).apply {
            val avatarSize = dp2px(ContactSceneSpec.REQUEST_AVATAR_DP.toFloat(), dm).toInt()
            layoutParams = LinearLayout.LayoutParams(avatarSize, avatarSize)
        }
        row.addView(avatar)

        val spacer = View(parent.context).apply {
            layoutParams = LinearLayout.LayoutParams(spacing, 1)
        }
        row.addView(spacer)

        val textColumn = LinearLayout(parent.context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val nameText = TextView(parent.context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ContactSceneSpec.REQUEST_NAME_SP.toFloat())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        // The peer's age / city pills ride right after the nickname, like the conversation list.
        val nameRow = LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LOCALE
        }
        nameRow.addView(nameText, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        val tagsSlot = FrameLayout(parent.context).apply { visibility = View.GONE }
        nameRow.addView(tagsSlot, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            marginStart = dp2px(6f, dm).toInt()
        })
        nameRow.addView(View(parent.context), LinearLayout.LayoutParams(0, 0, 1f))
        textColumn.addView(nameRow)

        val wordingText = TextView(parent.context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ContactSceneSpec.REQUEST_MESSAGE_SP.toFloat())
            setPadding(0, dp2px(2f, dm).toInt(), 0, 0)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        textColumn.addView(wordingText)

        row.addView(textColumn)

        val buttonRow = LinearLayout(parent.context).apply {
            orientation = LinearLayout.HORIZONTAL
            val endPad = dp2px(16f, dm).toInt()
            setPaddingRelative(0, 0, endPad, 0)
            val buttonSpacing = dp2px(10f, dm).toInt()
            gravity = Gravity.CENTER_VERTICAL
        }

        val buttonPad = dp2px(ContactSceneSpec.REQUEST_BUTTON_PADDING_DP.toFloat(), dm).toInt()
        val buttonHeight = dp2px(ContactSceneSpec.REQUEST_BUTTON_HEIGHT_DP.toFloat(), dm).toInt()
        val cornerRadius = dp2px(ContactSceneSpec.REQUEST_BUTTON_RADIUS_DP.toFloat(), dm)

        val agreeBtn = TextView(parent.context).apply {
            text = parent.context.getString(R.string.contact_list_agree)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ContactSceneSpec.REQUEST_BUTTON_SP.toFloat())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(buttonPad, 0, buttonPad, 0)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, buttonHeight).apply {
                marginEnd = dp2px(8f, dm).toInt()
            }
        }
        buttonRow.addView(agreeBtn)

        val refuseBtn = TextView(parent.context).apply {
            text = parent.context.getString(R.string.contact_list_refuse)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ContactSceneSpec.REQUEST_BUTTON_SP.toFloat())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(buttonPad, 0, buttonPad, 0)
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, buttonHeight)
        }
        buttonRow.addView(refuseBtn)

        row.addView(buttonRow)

        val addedText = TextView(parent.context).apply {
            text = parent.context.getString(R.string.contact_list_added)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, ContactSceneSpec.REQUEST_ADDED_SP.toFloat())
            gravity = Gravity.CENTER
            setPaddingRelative(0, 0, dp2px(16f, dm).toInt(), 0)
            visibility = View.GONE
        }
        row.addView(addedText)

        return ViewHolder(row, avatar, nameText, tagsSlot, wordingText, agreeBtn, refuseBtn, buttonRow, addedText, cornerRadius)
    }

    override fun onBindViewHolder(viewHolder: RecyclerView.ViewHolder, position: Int) {
        if (viewHolder is HeaderHolder) {
            viewHolder.title.text = context.getString(R.string.contact_list_received_group)
            viewHolder.title.setTextColor(colors.textColorTertiary)
            viewHolder.title.setBackgroundColor(colors.bgColorInput)
            return
        }
        val holder = viewHolder as ViewHolder
        val application = items[position - 1]

        holder.itemView.setOnClickListener { onItemClick(application) }

        val avatarUrl = application.avatarURL
        if (!avatarUrl.isNullOrEmpty()) {
            holder.avatar.setContent(AvatarContent.Image(avatarUrl, application.displayName))
        } else {
            holder.avatar.setContent(AvatarContent.Text(application.displayName))
        }

        holder.nameText.text = application.displayName
        holder.nameText.setTextColor(colors.textColorPrimary)
        holder.tagsSlot.removeAllViews()
        val tags = peerTags?.invoke(application.userID)
        if (tags != null) holder.tagsSlot.addView(tags)
        holder.tagsSlot.visibility = if (tags == null) View.GONE else View.VISIBLE

        holder.wordingText.text = application.addWording ?: ""
        holder.wordingText.setTextColor(colors.textColorSecondary)

        val agreeDrawable = GradientDrawable().apply {
            cornerRadius = holder.cornerRadius
            setColor(this@FriendApplicationAdapter.colors.buttonColorPrimaryDefault)
        }
        holder.agreeBtn.background = agreeDrawable
        holder.itemView.setBackgroundColor(colors.bgColorTopBar)
        holder.agreeBtn.setTextColor(colors.textColorButton)
        holder.agreeBtn.setOnClickListener { onAccept(application) }

        val refuseDrawable = GradientDrawable().apply {
            cornerRadius = holder.cornerRadius
            setStroke(
                context.resources.displayMetrics.density.toInt().coerceAtLeast(1),
                this@FriendApplicationAdapter.colors.strokeColorSecondary
            )
            setColor(0x00000000)
        }
        holder.refuseBtn.background = refuseDrawable
        holder.refuseBtn.setTextColor(colors.textColorSecondary)
        holder.refuseBtn.setOnClickListener { onRefuse(application) }

        val accepted = isAccepted(application.userID)
        holder.buttonRow.visibility = if (accepted) View.GONE else View.VISIBLE
        holder.addedText.visibility = if (accepted) View.VISIBLE else View.GONE
        holder.addedText.setTextColor(colors.textColorTertiary)
    }

    override fun getItemCount(): Int = if (items.isEmpty()) 0 else items.size + 1

    class HeaderHolder(val title: TextView) : RecyclerView.ViewHolder(title)

    private companion object {
        const val TYPE_HEADER = 0
        const val TYPE_ROW = 1
    }

    class ViewHolder(
        itemView: View,
        val avatar: Avatar,
        val nameText: TextView,
        val tagsSlot: FrameLayout,
        val wordingText: TextView,
        val agreeBtn: TextView,
        val refuseBtn: TextView,
        val buttonRow: LinearLayout,
        val addedText: TextView,
        val cornerRadius: Float
    ) : RecyclerView.ViewHolder(itemView)
}
