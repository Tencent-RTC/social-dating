import Foundation

public protocol HomeDataSource: AnyObject {
    /// Cities, sections and the first page of every section.
    func loadFeed(completion: @escaping (Result<HomeFeed, Error>) -> Void)

    /// Pull-to-refresh and "换一批": a fresh first page of `sectionId` that replaces what is on screen.
    /// An empty page keeps the current list.
    func refresh(sectionId: String, completion: @escaping (Result<HomePage, Error>) -> Void)

    /// The page after `cursor` (the `nextCursor` of the previous page). The page calls it while the user is still a few
    /// rows away from the end, never twice for the same cursor at once, and appends the result (cards already shown are
    /// skipped by `HomeUserCard.id`). A failure shows a retry row at the end of the list.
    func loadMore(sectionId: String, cursor: String, completion: @escaping (Result<HomePage, Error>) -> Void)

    func loadUserDetail(userKey: String, completion: @escaping (Result<HomeUserDetail, Error>) -> Void)
}

public struct HomeUserCard {
    public let id: String
    public let userId: String
    public let displayName: String
    public let age: Int
    public let sex: String
    public let city: String
    public let distanceKm: Double
    public let height: Int
    public let tags: [String]
    public let activity: String
    public let bio: String
    public let photo: String
    public let avatar: String

    public init(id: String, userId: String, displayName: String, age: Int, sex: String, city: String, distanceKm: Double,
                height: Int = 0, tags: [String], activity: String, bio: String, photo: String, avatar: String) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.age = age
        self.sex = sex
        self.city = city
        self.distanceKm = distanceKm
        self.height = height
        self.tags = tags
        self.activity = activity
        self.bio = bio
        self.photo = photo
        self.avatar = avatar
    }
}

extension HomeUserCard: Hashable {
    public static func == (lhs: HomeUserCard, rhs: HomeUserCard) -> Bool { lhs.id == rhs.id }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One page of a section. `nextCursor` is an opaque token handed back to `loadMore`; `nil` means the last page.
public struct HomePage {
    public let cards: [HomeUserCard]
    public let nextCursor: String?

    public init(cards: [HomeUserCard], nextCursor: String? = nil) {
        self.cards = cards
        self.nextCursor = nextCursor
    }
}

/// `cards` is the first page; `nextCursor` continues it (`nil` = nothing more to load).
public struct HomeSection {
    public let id: String
    public let title: String
    public let cards: [HomeUserCard]
    public let nextCursor: String?

    public init(id: String, title: String, cards: [HomeUserCard], nextCursor: String? = nil) {
        self.id = id
        self.title = title
        self.cards = cards
        self.nextCursor = nextCursor
    }
}

public struct HomeFeed {
    public let city: String
    public let sections: [HomeSection]

    public init(city: String, sections: [HomeSection]) {
        self.city = city
        self.sections = sections
    }
}

public struct HomeProfileInterest {
    public let text: String
    public let level: Int

    public init(text: String, level: Int) {
        self.text = text
        self.level = level
    }
}

public struct HomeProfileFact {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct HomeProfilePost {
    public let id: String
    public let sub: String
    public let text: String
    public let photos: [String]
    public let topic: String
    public let likes: Int
    public let comments: Int

    public init(id: String, sub: String, text: String, photos: [String], topic: String, likes: Int, comments: Int) {
        self.id = id
        self.sub = sub
        self.text = text
        self.photos = photos
        self.topic = topic
        self.likes = likes
        self.comments = comments
    }
}

public struct HomeUserDetail {
    public let card: HomeUserCard
    public let meta: String
    public let voiceSeconds: Int
    public let bio: String
    public let interests: [HomeProfileInterest]
    public let matchScore: Int
    public let matchText: String
    public let facts: [HomeProfileFact]
    public let albumCount: Int
    public let albumPhotos: [String]
    public let postCount: Int
    public let posts: [HomeProfilePost]

    public init(card: HomeUserCard, meta: String, voiceSeconds: Int, bio: String, interests: [HomeProfileInterest], matchScore: Int,
                matchText: String, facts: [HomeProfileFact], albumCount: Int, albumPhotos: [String], postCount: Int, posts: [HomeProfilePost]) {
        self.card = card
        self.meta = meta
        self.voiceSeconds = voiceSeconds
        self.bio = bio
        self.interests = interests
        self.matchScore = matchScore
        self.matchText = matchText
        self.facts = facts
        self.albumCount = albumCount
        self.albumPhotos = albumPhotos
        self.postCount = postCount
        self.posts = posts
    }
}
