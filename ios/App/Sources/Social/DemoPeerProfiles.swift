import Foundation
import TUIHostBase
import UIKit

struct DemoPeerProfile {
    let fixtureID: String
    let userID: String
    let name: String
    let age: Int
    let sex: String
    let city: String
    let distanceKm: Double
    let height: Int
    let activity: String
    let avatar: String
    let score: Int
    let matchText: String
    let interests: [String]

    var subtitle: String { DemoPeerProfiles.subtitle(city: city, height: height, age: age) }
}

enum DemoPeerProfiles {
    static func subtitle(city: String, height: Int, age: Int) -> String {
        let heightText = height > 0 ? DemoText.get("demo_height_cm", "\(height)") : ""
        let ageText = age > 0 ? DemoText.get("demo_age_years", "\(age)") : ""
        return [city, heightText, ageText].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func forUser(_ userID: String) -> DemoPeerProfile? {
        guard !userID.isEmpty, let fixtureID = bindings().first(where: { $0.value == userID })?.key else { return nil }
        return forFixture(fixtureID, userID: userID)
    }

    static func forFixture(_ fixtureID: String, userID: String = "") -> DemoPeerProfile? {
        guard let card = findCard(fixtureID) else { return nil }
        let profiles = (DemoFixtures.resolvedJSON("profiles") as? [String: Any])?["profiles"] as? [String: Any]
        let profile = profiles?[fixtureID] as? [String: Any]
        let match = profile?["match"] as? [String: Any]
        var interests = (profile?["interests"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        if interests.isEmpty { interests = card["tags"] as? [String] ?? [] }
        let height = (profile?["facts"] as? [[String: Any]])?
            .first
            .flatMap { Int(($0["v"] as? String ?? "").replacingOccurrences(of: "cm", with: "")) } ?? 0
        return DemoPeerProfile(
            fixtureID: fixtureID,
            userID: userID.isEmpty ? (bindings()[fixtureID] ?? "") : userID,
            name: card["displayName"] as? String ?? "",
            age: card["age"] as? Int ?? 0,
            sex: card["sex"] as? String ?? "f",
            city: card["city"] as? String ?? "",
            distanceKm: card["distanceKm"] as? Double ?? 0,
            height: height,
            activity: card["activity"] as? String ?? "",
            avatar: card["avatar"] as? String ?? "",
            score: match?["score"] as? Int ?? 0,
            matchText: match?["text"] as? String ?? "",
            interests: interests.filter { !$0.isEmpty }
        )
    }

    private static func findCard(_ fixtureID: String) -> [String: Any]? {
        guard let sections = (DemoFixtures.resolvedJSON("home") as? [String: Any])?["sections"] as? [[String: Any]] else { return nil }
        for section in sections {
            for key in ["cards", "altCards"] {
                if let card = (section[key] as? [[String: Any]])?.first(where: { $0["fixtureId"] as? String == fixtureID }) {
                    return card
                }
            }
        }
        return nil
    }

    private static func bindings() -> [String: String] {
        guard let list = (DemoFixtures.resolvedJSON("demo-peer-bindings") as? [String: Any])?["bindings"] as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for item in list {
            if let fixture = item["fixtureId"] as? String, let user = item["boundUserId"] as? String { out[fixture] = user }
        }
        return out
    }
}

enum DemoPeerTags {
    private static var cache: [String: DemoPeerProfile?] = [:]

    static func inline(peerID: String, height: CGFloat = HostMetrics.sexTagH) -> UIView? {
        guard !peerID.isEmpty, let profile = profile(peerID) else { return nil }
        return build(profile, height: height)
    }

    /// Everything the demo knows about the peer — city, age, height — for the friend-application detail page.
    static func full(peerID: String, height: CGFloat = HostMetrics.sexTagH) -> UIView? {
        guard !peerID.isEmpty, let profile = profile(peerID), let row = build(profile, height: height) else { return nil }
        guard let stack = row as? UIStackView, profile.height > 0 else { return row }
        stack.addArrangedSubview(Host.kindTag(.height, DemoText.get("demo_height_cm", "\(profile.height)"),
                                              height: height, radius: 8))
        return stack
    }

    private static func profile(_ peerID: String) -> DemoPeerProfile? {
        if let cached = cache[peerID] { return cached }
        let loaded = DemoPeerProfiles.forUser(peerID)
        cache[peerID] = loaded
        return loaded
    }

    static func build(_ profile: DemoPeerProfile, height: CGFloat = HostMetrics.sexTagH) -> UIView? {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        if profile.age > 0 {
            row.addArrangedSubview(Host.sexTag(sex: profile.sex, age: profile.age))
        }
        if !profile.city.isEmpty {
            row.addArrangedSubview(Host.kindTag(.city, profile.city, height: height, radius: 8))
        }
        return row.arrangedSubviews.isEmpty ? nil : row
    }
}
