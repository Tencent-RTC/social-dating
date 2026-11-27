package io.trtc.tuikit.chat.mine

import io.trtc.tuikit.chat.hostbase.SocialToast
import android.app.DatePickerDialog
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import io.trtc.tuikit.atomicxcore.api.CompletionHandler
import io.trtc.tuikit.atomicxcore.api.login.Gender
import io.trtc.tuikit.atomicxcore.api.login.LoginStore
import io.trtc.tuikit.atomicxcore.api.login.UserProfile
import io.trtc.tuikit.chat.hostbase.AvatarView
import io.trtc.tuikit.chat.hostbase.DemoActivity
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostHeader
import io.trtc.tuikit.chat.hostbase.HostMetrics
import io.trtc.tuikit.chat.hostbase.R as BaseR
import io.trtc.tuikit.chat.mine.R
import io.trtc.tuikit.chat.uikit.components.chatsetting.ui.TextInputDialog
import io.trtc.tuikit.chat.uikit.components.widgets.ActionItem
import io.trtc.tuikit.chat.uikit.components.widgets.ActionSheet
import io.trtc.tuikit.chat.uikit.components.widgets.AvatarPickerDialog
import java.util.Calendar
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Edit profile sub page of 「我的」. Same data path as the Chat View Demo's self-detail page: every field is
 * the real IM profile, read from `LoginStore.loginUserInfo` and written back with `LoginStore.setSelfInfo`
 * (an incremental update, only the changed field is set). The look follows the 1v1 host: 17sp title bar, a
 * centred 88dp avatar and one list surface with 52dp rows.
 */
class EditProfileActivity : DemoActivity() {
    private val tokens get() = DemoUi.tokens
    private var scope: CoroutineScope? = null
    private lateinit var avatar: LinearLayout
    private lateinit var rows: LinearLayout

    private var profile: UserProfile? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(tokens.bgColorTopBar)
        }
        setContentView(page)
        immersive(page, tokens.bgColorTopBar, bodyColor = tokens.bgColorTopBar)
        val back = Host.backButton(this) { finish() }
        page.addView(HostHeader(this, DemoText.get(R.string.demo_edit_profile), left = back))
        avatar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        rows = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(tokens.bgColorTopBar)
        }
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(avatar, LinearLayout.LayoutParams(-1, -2))
            addView(rows, LinearLayout.LayoutParams(-1, -2).apply { topMargin = Host.dp(this@EditProfileActivity, HostMetrics.ME_BLOCK_GAP) })
        }
        page.addView(ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            setBackgroundColor(tokens.bgColorDefault)
            addView(body)
        }, LinearLayout.LayoutParams(-1, 0, 1f))

        scope = CoroutineScope(Dispatchers.Main + SupervisorJob()).also { s ->
            s.launch {
                LoginStore.shared.loginState.loginUserInfo.collectLatest {
                    profile = it
                    render()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope?.cancel()
        scope = null
    }

    private fun render() {
        val data = profile ?: return
        val name = data.nickname?.takeIf { it.isNotBlank() } ?: data.userID
        avatar.removeAllViews()
        val pad = Host.dp(this, 20)
        avatar.setPadding(0, pad, 0, pad)
        avatar.setBackgroundColor(tokens.bgColorTopBar)
        avatar.addView(AvatarView(this, name, DemoUi.ACCENT, 88).also { it.load(data.avatarURL) }.apply {
            contentDescription = DemoText.get(R.string.demo_change_avatar)
            setOnClickListener { pickAvatar() }
        })
        avatar.addView(Host.text(this, DemoText.get(R.string.demo_change_avatar), 14f, tokens.textColorLink),
            LinearLayout.LayoutParams(-2, -2).apply { topMargin = Host.dp(this@EditProfileActivity, 8) })

        rows.removeAllViews()
        rows.addView(row(DemoText.get(R.string.demo_account_id), data.userID, onClick = null))
        rows.addView(row(DemoText.get(R.string.demo_nickname), data.nickname.orEmpty()) { editNickname(data.nickname.orEmpty()) })
        rows.addView(row(DemoText.get(R.string.demo_signature),
            data.selfSignature?.takeIf { it.isNotBlank() } ?: DemoText.get(R.string.demo_signature_empty)) { editSignature(data.selfSignature.orEmpty()) })
        rows.addView(row(DemoText.get(R.string.demo_gender), genderText(data.gender)) { pickGender() })
        rows.addView(row(DemoText.get(R.string.demo_birthday), birthdayText(data.birthday), last = true, onClick = { pickBirthday(data.birthday) }))
    }

    private fun row(title: String, value: String, last: Boolean = false, onClick: (() -> Unit)? = null): View {
        val pad = Host.dp(this, HostMetrics.SCREEN_PADDING_H)
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(LinearLayout(this@EditProfileActivity).apply {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(pad, 0, pad, 0)
                addView(Host.text(this@EditProfileActivity, title, 17f, tokens.textColorPrimary), LinearLayout.LayoutParams(Host.dp(this@EditProfileActivity, 100), -2))
                addView(Host.text(this@EditProfileActivity, value, 15f, tokens.textColorSecondary, single = true).apply {
                    gravity = Gravity.END or Gravity.CENTER_VERTICAL
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }, LinearLayout.LayoutParams(0, -2, 1f))
                if (onClick != null) {
                    addView(Host.icon(this@EditProfileActivity, BaseR.drawable.demo_ic_chevron, 12, tokens.textColorDisable),
                        LinearLayout.LayoutParams(-2, -2).apply { marginStart = Host.dp(this@EditProfileActivity, 8) })
                    setOnClickListener { onClick() }
                }
            }, LinearLayout.LayoutParams(-1, Host.dp(this@EditProfileActivity, 56)))
            if (!last) addView(View(this@EditProfileActivity).apply { setBackgroundColor(tokens.strokeColorPrimary) },
                LinearLayout.LayoutParams(-1, 1).apply { marginStart = pad })
        }
    }

    private fun genderText(gender: Gender?) = DemoText.get(when (gender) {
        Gender.MALE -> R.string.demo_gender_male
        Gender.FEMALE -> R.string.demo_gender_female
        else -> R.string.demo_gender_secret
    })

    private fun birthdayText(birthday: Long?): String {
        val raw = birthday?.takeIf { it > 0 }?.toString()?.takeIf { it.length == 8 } ?: return DemoText.get(R.string.demo_signature_empty)
        return "${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}"
    }

    private fun pickAvatar() {
        val urls = (1..26).map { "https://im.sdk.qcloud.com/download/tuikit-resource/avatar/avatar_$it.png" }
        AvatarPickerDialog(this, DemoText.get(R.string.demo_pick_avatar), urls) { _, url ->
            save(UserProfile(avatarURL = url))
        }.show()
    }

    private fun editNickname(current: String) {
        TextInputDialog(this, DemoText.get(R.string.demo_edit_nickname), current, maxLength = 32) { text ->
            if (text.isNotBlank()) save(UserProfile(nickname = text.trim()))
        }.show()
    }

    private fun editSignature(current: String) {
        TextInputDialog(this, DemoText.get(R.string.demo_edit_signature), current, maxLength = 60, multiline = true) { text ->
            save(UserProfile(selfSignature = text.trim()))
        }.show()
    }

    private fun pickGender() {
        val options = listOf(
            ActionItem(DemoText.get(R.string.demo_gender_male), value = Gender.MALE),
            ActionItem(DemoText.get(R.string.demo_gender_female), value = Gender.FEMALE),
            ActionItem(DemoText.get(R.string.demo_gender_secret), value = Gender.UNKNOWN)
        )
        ActionSheet.show(this, options) { picked -> save(UserProfile(gender = picked.value as? Gender ?: Gender.UNKNOWN)) }
    }

    private fun pickBirthday(birthday: Long?) {
        val cal = Calendar.getInstance()
        val raw = birthday?.takeIf { it > 0 }?.toString()
        if (raw != null && raw.length == 8) {
            runCatching { cal.set(raw.substring(0, 4).toInt(), raw.substring(4, 6).toInt() - 1, raw.substring(6, 8).toInt()) }
        } else {
            cal.set(2000, 0, 1)
        }
        DatePickerDialog(this, { _, year, month, day ->
            save(UserProfile(birthday = (year * 10000L + (month + 1) * 100L + day)))
        }, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)).apply {
            datePicker.maxDate = System.currentTimeMillis()
        }.show()
    }

    /** Incremental update: only the field that is set in [change] is written (same as Chat View Demo). */
    private fun save(change: UserProfile) {
        LoginStore.shared.setSelfInfo(change, object : CompletionHandler {
            override fun onSuccess() = Unit
            override fun onFailure(code: Int, desc: String) {
                runOnUiThread { SocialToast.show(this@EditProfileActivity, DemoText.get(R.string.demo_profile_save_failed), SocialToast.Kind.ERROR) }
            }
        })
    }
}
