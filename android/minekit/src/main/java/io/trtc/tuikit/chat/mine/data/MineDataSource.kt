package io.trtc.tuikit.chat.mine.data

interface MineDataSource {
    fun loadContent(completion: (Result<MineContent>) -> Unit)
}

data class MineTag(val type: String, val text: String)

data class MineWallet(
    val label: String,
    val balance: String,
    val promo: String,
    val promoPre: String,
    val promoBonus: String,
    val action: String
)

data class MineMenuItem(val id: String, val icon: String, val title: String, val value: String)

data class MineContent(
    val signature: String,
    val city: String,
    val tags: List<MineTag>,
    val editLabel: String,
    val wallet: MineWallet,
    val menuGroups: List<List<MineMenuItem>>
)

data class MineIdentity(
    val nickname: String,
    val userId: String,
    val avatar: String?,
    val signature: String,
    val idText: String? = null
)
