import Foundation

public protocol MineDataSource: AnyObject {
    func loadContent(completion: @escaping (Result<MineContent, Error>) -> Void)
}

public struct MineTag {
    public let type: String
    public let text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct MineWallet {
    public let label: String
    public let balance: String
    public let promo: String
    public let promoPre: String
    public let promoBonus: String
    public let action: String

    public init(label: String, balance: String, promo: String, promoPre: String, promoBonus: String, action: String) {
        self.label = label
        self.balance = balance
        self.promo = promo
        self.promoPre = promoPre
        self.promoBonus = promoBonus
        self.action = action
    }
}

public struct MineMenuItem {
    public let id: String
    public let icon: String
    public let title: String
    public let value: String

    public init(id: String, icon: String, title: String, value: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.value = value
    }
}

public struct MineContent {
    public let signature: String
    public let city: String
    public let tags: [MineTag]
    public let editLabel: String
    public let wallet: MineWallet
    public let menuGroups: [[MineMenuItem]]

    public init(signature: String, city: String, tags: [MineTag], editLabel: String, wallet: MineWallet,
                menuGroups: [[MineMenuItem]]) {
        self.signature = signature
        self.city = city
        self.tags = tags
        self.editLabel = editLabel
        self.wallet = wallet
        self.menuGroups = menuGroups
    }
}

public struct MineIdentity {
    public let nickname: String
    public let idText: String
    public let avatar: String

    public init(nickname: String, idText: String, avatar: String) {
        self.nickname = nickname
        self.idText = idText
        self.avatar = avatar
    }
}
