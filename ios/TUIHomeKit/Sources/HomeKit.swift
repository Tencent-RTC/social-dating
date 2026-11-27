import Foundation
import TUIHostBase
import UIKit

public enum HomeKit {
    private static var source: HomeDataSource?
    private static var handler: HomeActions?
    private static var details: [String: HomeUserDetail] = [:]

    public static func install(dataSource: HomeDataSource, actions: HomeActions) {
        source = dataSource
        handler = actions
        details.removeAll()
        HostResources.register(bundleName: "TUIHomeKitBundle", anchor: HomeKitAnchor.self)
    }

    public static var dataSource: HomeDataSource {
        guard let source else { fatalError("HomeKit.install must be called before the home pages are opened") }
        return source
    }

    public static var actions: HomeActions {
        guard let handler else { fatalError("HomeKit.install must be called before the home pages are opened") }
        return handler
    }

    public static func cachedDetail(_ userKey: String) -> HomeUserDetail? { details[userKey] }

    public static func cacheDetail(_ userKey: String, _ detail: HomeUserDetail) { details[userKey] = detail }

    public static func clearCache() { details.removeAll() }
}

private final class HomeKitAnchor {}

/// Result of the one-tap friend request: added right away, or waiting for the other side to approve.
public enum FriendAddOutcome {
    case added
    case pending
    case failed
}

public protocol HomeActions: AnyObject {
    func openChat(from controller: UIViewController, user: HomeUserCard)

    /// Sends the preset friend request (no remark, default wording); never opens the add-friend form.
    func addFriend(from controller: UIViewController, user: HomeUserCard, completion: @escaping (FriendAddOutcome) -> Void)

    func isFriend(user: HomeUserCard, completion: @escaping (Bool) -> Void)

    /// Removes the friend relation; `completion` is true once the store call succeeded.
    func deleteFriend(from controller: UIViewController, user: HomeUserCard, completion: @escaping (Bool) -> Void)

    func videoChat(from controller: UIViewController, user: HomeUserCard)

    func voiceSignatureTapped(from controller: UIViewController, user: HomeUserCard)

    func moreTapped(from controller: UIViewController, user: HomeUserCard)

    func albumPhotoTapped(from controller: UIViewController, user: HomeUserCard, photo: String)

    func commentTapped(from controller: UIViewController, user: HomeUserCard, post: HomeProfilePost)
}

public extension HomeActions {
    func openChat(from controller: UIViewController, user: HomeUserCard) {}

    func addFriend(from controller: UIViewController, user: HomeUserCard, completion: @escaping (FriendAddOutcome) -> Void) {
        completion(.failed)
    }

    func isFriend(user: HomeUserCard, completion: @escaping (Bool) -> Void) { completion(false) }

    func deleteFriend(from controller: UIViewController, user: HomeUserCard, completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func voiceSignatureTapped(from controller: UIViewController, user: HomeUserCard) {}

    func moreTapped(from controller: UIViewController, user: HomeUserCard) {}

    func albumPhotoTapped(from controller: UIViewController, user: HomeUserCard, photo: String) {}

    func commentTapped(from controller: UIViewController, user: HomeUserCard, post: HomeProfilePost) {}
}
