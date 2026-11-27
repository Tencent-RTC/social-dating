package io.trtc.tuikit.chat.home.ui

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.trtc.tuikit.chat.home.R
import io.trtc.tuikit.chat.home.data.HomeUserDetail
import io.trtc.tuikit.chat.hostbase.DemoText
import io.trtc.tuikit.chat.hostbase.DemoUi
import io.trtc.tuikit.chat.hostbase.Host
import io.trtc.tuikit.chat.hostbase.HostMetrics

/**
 * Ice-breaker card (design board M `702:271`): the first item of a 1v1 chat. It is not an IM message: it never counts
 * as unread, never enters the conversation summary and has no long-press menu. Pure view builder, all data comes from
 * [HomeUserDetail] (mock fixtures for now, no IM access).
 *
 * The returned view fills the height its host gives it (one third of the chat page, see the message list header slot);
 * the card stretches inside and the hint line keeps its natural height underneath.
 */
object IcebreakerCard {
    /** Basic facts shown on the card: height, education, hometown. The income fact (index 2) stays on the profile page. */
    private val FACT_INDEXES = listOf(0, 1, 3)
    private const val MAX_FACTS = 3
    private const val MAX_TAGS = 3
    private const val MAX_THUMBS = 3

    class Actions(
        val onProfile: () -> Unit,
        val onAlbum: () -> Unit,
        val onVoicePlay: () -> Unit = {}
    )

    /** True when there is enough to show; a card with no photo and no facts is hidden by the host instead. */
    fun hasContent(detail: HomeUserDetail): Boolean =
        detail.card.photo.isNotBlank() && (detail.facts.isNotEmpty() || detail.interests.isNotEmpty())

    fun build(context: Context, detail: HomeUserDetail, actions: Actions): View {
        val c = DemoUi.tokens
        val dp = { value: Int -> Host.dp(context, value) }
        val card = detail.card

        val left = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(ProfileUi.photo(context, card.photo, 14f).apply {
                contentDescription = card.displayName
                setOnClickListener { actions.onProfile() }
            }, LinearLayout.LayoutParams(-1, 0, 1f))
            if (detail.albumPhotos.isNotEmpty()) {
                addView(thumbRow(context, detail, actions),
                    LinearLayout.LayoutParams(-1, dp(40)).apply { topMargin = dp(8) })
            }
        }

        val right = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(Host.text(context, card.displayName, HostMetrics.USER_CARD_NAME_SP, c.textColorPrimary,
                    bold = true, single = true), LinearLayout.LayoutParams(-2, -2, 0f))
                if (card.age > 0) {
                    addView(ProfileUi.solidSexTag(context, card.sex, card.age),
                        LinearLayout.LayoutParams(-2, dp(20)).apply { marginStart = dp(6) })
                }
            })
            subtitle(detail).takeIf { it.isNotBlank() }?.let {
                addView(Host.text(context, it, 12f, c.textColorSecondary, single = true),
                    LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(4) })
            }
            val facts = FACT_INDEXES.mapNotNull { detail.facts.getOrNull(it) }.take(MAX_FACTS)
            if (facts.isNotEmpty()) {
                addView(FitRow(context).apply {
                    facts.forEach { fact ->
                        addView(Host.text(context, fact.value, 11f, c.textColorSecondary, single = true).apply {
                            gravity = Gravity.CENTER
                            setPadding(dp(8), 0, dp(8), 0)
                            background = Host.rounded(context, c.bgColorFunction, 10f)
                        }, LinearLayout.LayoutParams(-2, dp(20)).apply { marginEnd = dp(6) })
                    }
                }, LinearLayout.LayoutParams(-1, dp(20)).apply { topMargin = dp(8) })
            }
            if (detail.interests.isNotEmpty()) {
                addView(FitRow(context).apply {
                    detail.interests.take(MAX_TAGS).forEach { tag ->
                        addView(ProfileUi.interestTag(context, tag.text, tag.level),
                            LinearLayout.LayoutParams(-2, dp(26)).apply { marginEnd = dp(6) })
                    }
                }, LinearLayout.LayoutParams(-1, dp(26)).apply { topMargin = dp(6) })
            }
            if (detail.matchScore > 0 || detail.matchText.isNotBlank()) {
                addView(commonBox(context, detail), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
            }
            addView(View(context), LinearLayout.LayoutParams(-1, 0, 1f))
            if (detail.voiceSeconds > 0) {
                addView(ProfileUi.voiceButton(context, detail.voiceSeconds, actions.onVoicePlay),
                    LinearLayout.LayoutParams(-1, dp(32)).apply { topMargin = dp(8) })
            }
        }

        val body = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
            background = Host.rounded(context, c.bgColorEntryCard, 20f, c.strokeColorPrimary)
            addView(left, LinearLayout.LayoutParams(dp(124), -1))
            addView(right, LinearLayout.LayoutParams(0, -1, 1f).apply { marginStart = dp(12) })
        }

        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(HostMetrics.SCREEN_PADDING_H), dp(12), dp(HostMetrics.SCREEN_PADDING_H), dp(6))
            addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
            // A small pill, so the line stays readable over any chat background (the light theme keeps the dark starry one).
            addView(Host.text(context, DemoText.get(R.string.demo_icebreaker_hint), 12f, c.textColorSecondary).apply {
                gravity = Gravity.CENTER
                setPadding(dp(12), dp(4), dp(12), dp(4))
                background = Host.rounded(context, c.bgColorEntryCard, 12f)
            }, LinearLayout.LayoutParams(-2, -2, 0f).apply {
                topMargin = dp(8)
                gravity = Gravity.CENTER_HORIZONTAL
            })
        }
    }

    /** 「深圳 · 巨蟹座 · 独立音乐人」: the profile meta without the leading distance segment. */
    private fun subtitle(detail: HomeUserDetail): String {
        val raw = detail.meta.ifBlank { detail.card.city }
        return raw.split(" · ").filterNot { it.matches(Regex("^\\d+(\\.\\d+)?km$")) }.joinToString(" · ")
    }

    /** Three 36x40 album thumbnails; when the album holds more, the last one carries a 50% scrim with 「+N」. */
    private fun thumbRow(context: Context, detail: HomeUserDetail, actions: Actions): View {
        val dp = { value: Int -> Host.dp(context, value) }
        val shown = detail.albumPhotos.take(MAX_THUMBS)
        val more = detail.albumCount - shown.size
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            shown.forEachIndexed { index, name ->
                val last = index == shown.lastIndex && more > 0
                addView(FrameLayout(context).apply {
                    contentDescription = DemoText.get(R.string.demo_album)
                    addView(ProfileUi.photo(context, name, 8f), FrameLayout.LayoutParams(-1, -1))
                    if (last) {
                        addView(Host.text(context, "+$more", 12f, 0xFFFFFFFF.toInt(), bold = true).apply {
                            gravity = Gravity.CENTER
                            background = Host.rounded(context, 0x80000000.toInt(), 8f)
                        }, FrameLayout.LayoutParams(-1, -1))
                    }
                    setOnClickListener { actions.onAlbum() }
                }, LinearLayout.LayoutParams(dp(36), dp(40)).apply { if (index > 0) marginStart = dp(8) })
            }
        }
    }

    /** Common-ground box: a 「缘分 88」 capsule and the one-line reason. */
    private fun commonBox(context: Context, detail: HomeUserDetail): View {
        val c = DemoUi.tokens
        val dp = { value: Int -> Host.dp(context, value) }
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = Host.rounded(context, c.bgColorFunction, 10f)
            if (detail.matchScore > 0) {
                addView(Host.text(context, DemoText.get(R.string.demo_icebreaker_match, detail.matchScore), 11f,
                    c.textColorWarning, bold = true).apply {
                    gravity = Gravity.CENTER
                    setPadding(dp(6), 0, dp(6), 0)
                    background = Host.rounded(context, Host.alpha(c.textColorWarning, 0.16f), 8f)
                }, LinearLayout.LayoutParams(-2, dp(16)).apply { marginEnd = dp(6) })
            }
            if (detail.matchText.isNotBlank()) {
                addView(Host.text(context, detail.matchText, 12f, c.textColorPrimary).apply { maxLines = 2 },
                    LinearLayout.LayoutParams(0, -2, 1f))
            }
        }
    }

    /** Horizontal row that hides the children that no longer fit, so a narrow phone drops the last chip instead of clipping it. */
    private class FitRow(context: Context) : LinearLayout(context) {
        init { orientation = HORIZONTAL }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            var used = 0
            var full = false
            val available = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
            for (i in 0 until childCount) {
                val child = getChildAt(i)
                child.visibility = View.VISIBLE
                child.measure(MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
                    MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
                val lp = child.layoutParams as MarginLayoutParams
                val need = child.measuredWidth + lp.marginEnd
                if (full || used + need > available + lp.marginEnd) {
                    full = true
                    child.visibility = View.GONE
                } else {
                    used += need
                }
            }
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        }
    }
}
