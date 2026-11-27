import Foundation
import TUIHomeKit
import TUIHostBase
import TUIMineKit

final class DemoHomeDataSource: HomeDataSource {
    private struct Card: Decodable {
        let fixtureId: String
        let displayName: String
        let age: Int
        let city: String
        let distanceKm: Double
        let tags: [String]
        let bio: String
        let sex: String
        let activity: String
        let photo: String
        let avatar: String
    }

    private struct Section: Decodable {
        let id: String
        let title: String
        let cards: [Card]
        let altCards: [Card]
    }

    private struct Home: Decodable { let sections: [Section] }
    private struct Binding: Decodable { let fixtureId: String; let boundUserId: String }
    private struct Bindings: Decodable { let bindings: [Binding] }
    private struct LoginPreset: Decodable { let userId: String }
    private struct LoginPresets: Decodable { let presets: [LoginPreset] }

    private struct Detail: Decodable {
        struct Interest: Decodable { let text: String; let level: Int }
        struct Fact: Decodable { let v: String; let l: String }
        struct Match: Decodable { let score: Int; let text: String }
        struct Album: Decodable { let count: Int; let photos: [String] }
        struct Post: Decodable {
            let id: String
            let sub: String
            let text: String
            let photos: [String]
            let topic: String
            let likes: Int
            let comments: Int
        }
        struct Posts: Decodable { let count: Int; let items: [Post] }
        let meta: String
        let voice: Int
        let bio: String
        let interests: [Interest]
        let match: Match
        let facts: [Fact]
        let album: Album
        let posts: Posts
    }

    private struct Profiles: Decodable { let profiles: [String: Detail] }

    private struct Missing: Error {}

    private let queue = DispatchQueue(label: "demo.home.data")

    private lazy var heightByFixture: [String: Int] = {
        guard let profiles = DemoFixtures.load(Profiles.self, "profiles") else { return [:] }
        var out: [String: Int] = [:]
        for (id, detail) in profiles.profiles {
            guard let fact = detail.facts.first else { continue }
            if let cm = Int(fact.v.replacingOccurrences(of: "cm", with: "")) { out[id] = cm }
        }
        return out
    }()
    private var alternate = Set<String>()
    private let pinnedSections: Set<String> = ["recommend"]
    private lazy var presetUserIds: [String] = DemoFixtures.load(LoginPresets.self, "login-presets")?.presets.map { $0.userId } ?? []

    func loadFeed(completion: @escaping (Result<HomeFeed, Error>) -> Void) {
        queue.async { [self] in
            alternate.removeAll()
            let result: Result<HomeFeed, Error> = orderedSections().map { sections in
                HomeFeed(city: DemoText.get("demo_shenzhen"), sections: sections.map {
                    let first = page(cards($0.cards), offset: 0, order: "main")
                    return HomeSection(id: $0.id, title: $0.title, cards: first.cards, nextCursor: first.nextCursor)
                })
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func refresh(sectionId: String, completion: @escaping (Result<HomePage, Error>) -> Void) {
        queue.async { [self] in
            let result: Result<HomePage, Error> = orderedSections().flatMap { sections in
                guard let section = sections.first(where: { $0.id == sectionId }) else { return .failure(Missing()) }
                let useAlt = alternate.remove(sectionId) == nil && alternate.insert(sectionId).inserted
                if useAlt && !section.altCards.isEmpty { return .success(page(cards(section.altCards), offset: 0, order: "alt")) }
                return .success(page(cards(section.cards), offset: 0, order: "main"))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// The cursor is `<order>:<offset>`; the demo pool (one fixture list) is cut into `pageSize` cards per page.
    func loadMore(sectionId: String, cursor: String, completion: @escaping (Result<HomePage, Error>) -> Void) {
        queue.async { [self] in
            let result: Result<HomePage, Error> = orderedSections().flatMap { sections in
                guard let section = sections.first(where: { $0.id == sectionId }) else { return .failure(Missing()) }
                let parts = cursor.split(separator: ":")
                guard parts.count == 2, let offset = Int(parts[1]) else { return .failure(Missing()) }
                let alt = parts[0] == "alt" && !section.altCards.isEmpty
                return .success(page(cards(alt ? section.altCards : section.cards), offset: offset, order: alt ? "alt" : "main"))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadMoreLatency) { completion(result) }
        }
    }

    private static let pageSize = 8
    private static let loadMoreLatency: TimeInterval = 0.45

    private func page(_ all: [HomeUserCard], offset: Int, order: String) -> HomePage {
        let end = min(offset + Self.pageSize, all.count)
        let start = min(offset, end)
        return HomePage(cards: Array(all[start..<end]), nextCursor: end < all.count ? "\(order):\(end)" : nil)
    }

    func loadUserDetail(userKey: String, completion: @escaping (Result<HomeUserDetail, Error>) -> Void) {
        queue.async { [self] in
            let result: Result<HomeUserDetail, Error> = rawSections().flatMap { sections in
                let all = sections.flatMap { $0.cards + $0.altCards }
                guard let raw = all.first(where: { $0.fixtureId == userKey }) else { return .failure(Missing()) }
                return .success(detail(card(raw)))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func rawSections() -> Result<[Section], Error> {
        guard let home = DemoFixtures.load(Home.self, "home") else { return .failure(Missing()) }
        return .success(home.sections)
    }

    private func orderedSections() -> Result<[Section], Error> {
        rawSections().map { sections in
            sections.map { section in
                guard pinnedSections.contains(section.id) else { return section }
                return Section(id: section.id, title: section.title, cards: pinnedCards(section.cards), altCards: section.altCards)
            }
        }
    }

    private func pinnedCards(_ cards: [Card]) -> [Card] {
        guard !presetUserIds.isEmpty else { return cards }
        var rank: [String: Int] = [:]
        for (index, userId) in presetUserIds.enumerated() { rank[userId] = index }
        let bound = bindings()
        let pinned = cards
            .filter { rank[bound[$0.fixtureId] ?? ""] != nil }
            .sorted { (rank[bound[$0.fixtureId] ?? ""] ?? 0) < (rank[bound[$1.fixtureId] ?? ""] ?? 0) }
        let rest = cards.filter { rank[bound[$0.fixtureId] ?? ""] == nil }
        return pinned + rest
    }

    private func bindings() -> [String: String] {
        guard let value = DemoFixtures.load(Bindings.self, "demo-peer-bindings") else { return [:] }
        return Dictionary(value.bindings.map { ($0.fixtureId, $0.boundUserId) }, uniquingKeysWith: { first, _ in first })
    }

    private func card(_ raw: Card) -> HomeUserCard {
        HomeUserCard(
            id: raw.fixtureId,
            userId: bindings()[raw.fixtureId] ?? "",
            displayName: raw.displayName, age: raw.age, sex: raw.sex, city: raw.city, distanceKm: raw.distanceKm,
            height: heightByFixture[raw.fixtureId] ?? 0,
            tags: raw.tags, activity: raw.activity, bio: raw.bio, photo: raw.photo, avatar: raw.avatar
        )
    }

    /// Every IM demo account is listed except the one signed in on this device, so the Home tab always shows
    /// the other people (the card of your own account would only open a chat with yourself).
    private func cards(_ raw: [Card]) -> [HomeUserCard] {
        var seen = Set<String>()
        let bound = bindings()
        let me = DemoHostSession.accountId
        return raw
            .filter { seen.insert($0.fixtureId).inserted }
            .filter { me.isEmpty || bound[$0.fixtureId] != me }
            .map(card)
    }

    private func detail(_ card: HomeUserCard) -> HomeUserDetail {
        guard let raw = DemoFixtures.load(Profiles.self, "profiles")?.profiles[card.id] else {
            return HomeUserDetail(card: card, meta: "", voiceSeconds: 0, bio: "", interests: [], matchScore: 0, matchText: "",
                                  facts: [], albumCount: 0, albumPhotos: [], postCount: 0, posts: [])
        }
        return HomeUserDetail(
            card: card, meta: raw.meta, voiceSeconds: raw.voice, bio: raw.bio,
            interests: raw.interests.map { HomeProfileInterest(text: $0.text, level: $0.level) },
            matchScore: raw.match.score, matchText: raw.match.text,
            facts: raw.facts.map { HomeProfileFact(value: $0.v, label: $0.l) },
            albumCount: raw.album.count, albumPhotos: raw.album.photos,
            postCount: raw.posts.count,
            posts: raw.posts.items.map { HomeProfilePost(id: $0.id, sub: $0.sub, text: $0.text, photos: $0.photos, topic: $0.topic, likes: $0.likes, comments: $0.comments) }
        )
    }
}

final class DemoMineDataSource: MineDataSource {
    private struct Root: Decodable {
        struct Tag: Decodable { let type: String; let text: String }
        struct Profile: Decodable {
            let signature: String
            let city: String
            let tags: [Tag]
            let edit: String
        }
        struct Wallet: Decodable {
            let label: String
            let balance: String
            let promo: String
            let promoPre: String
            let promoBonus: String
            let action: String
        }
        struct MenuItem: Decodable { let id: String; let icon: String; let title: String; let value: String }
        let mockProfile: Profile
        let wallet: Wallet
        let menuGroups: [[MenuItem]]
    }

    private struct Missing: Error {}

    private let queue = DispatchQueue(label: "demo.mine.data")

    func loadContent(completion: @escaping (Result<MineContent, Error>) -> Void) {
        queue.async {
            let result: Result<MineContent, Error>
            if let root = DemoFixtures.load(Root.self, "mine") {
                result = .success(MineContent(
                    signature: root.mockProfile.signature, city: root.mockProfile.city,
                    tags: root.mockProfile.tags.map { MineTag(type: $0.type, text: $0.text) },
                    editLabel: root.mockProfile.edit,
                    wallet: MineWallet(label: root.wallet.label, balance: root.wallet.balance, promo: root.wallet.promo,
                                       promoPre: root.wallet.promoPre, promoBonus: root.wallet.promoBonus, action: root.wallet.action),
                    menuGroups: root.menuGroups.map { group in group.map { MineMenuItem(id: $0.id, icon: $0.icon, title: $0.title, value: $0.value) } }
                ))
            } else {
                result = .failure(Missing())
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
