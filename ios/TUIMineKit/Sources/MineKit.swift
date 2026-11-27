import Foundation
import TUIHostBase
import UIKit

public enum MineKit {
    private static var source: MineDataSource?
    private static var handler: MineActions?

    public static func install(dataSource: MineDataSource, actions: MineActions) {
        source = dataSource
        handler = actions
        HostResources.register(bundleName: "TUIMineKitBundle", anchor: MineKitAnchor.self)
    }

    public static var dataSource: MineDataSource {
        guard let source else { fatalError("MineKit.install must be called before the mine pages are opened") }
        return source
    }

    public static var actions: MineActions {
        guard let handler else { fatalError("MineKit.install must be called before the mine pages are opened") }
        return handler
    }
}

private final class MineKitAnchor {}

public protocol MineActions: AnyObject {
    func walletTapped(from controller: UIViewController)

    func menuItemTapped(from controller: UIViewController, item: MineMenuItem)

    func editProfileTapped(from controller: UIViewController) -> Bool

    /// Whether the Mine tab offers 退出登录 (false in the logged-out preview).
    func isLogoutAvailable() -> Bool

    /// Called after the user confirmed; the host signs out of IM and returns to its login screen.
    func logoutConfirmed(from controller: UIViewController)

    /// Presents the language bottom sheet; the choice is applied immediately and announced through `DemoLanguage.didChange`.
    func showLanguagePicker(from controller: UIViewController)

    /// Presents the appearance (mode + palette) bottom sheet; changes are announced through `DemoThemeCoordinator.didChange`.
    func showAppearancePicker(from controller: UIViewController)

    /// Presents the「加好友」verification rule sheet; `completion` runs after the new rule was saved.
    func showFriendAddRulePicker(from controller: UIViewController, completion: @escaping () -> Void)
}

public extension MineActions {
    func walletTapped(from controller: UIViewController) {}

    func menuItemTapped(from controller: UIViewController, item: MineMenuItem) {}

    func editProfileTapped(from controller: UIViewController) -> Bool { true }

    func isLogoutAvailable() -> Bool { false }

    func logoutConfirmed(from controller: UIViewController) {}

    func showLanguagePicker(from controller: UIViewController) {}

    func showAppearancePicker(from controller: UIViewController) {}

    func showFriendAddRulePicker(from controller: UIViewController, completion: @escaping () -> Void) {}
}
