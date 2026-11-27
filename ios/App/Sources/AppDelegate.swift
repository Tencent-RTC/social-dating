import UIKit
import AtomicXCore
import AtomicX
import TUIChatKit
import TUICallKit
import TUIHomeKit
import TUIMineKit
import TUIHostBase

/// Login entry only asks for a userID; the V2 host takes over after login.
/// [DEMO_LOCAL_AUTH] Signs locally using SDKAppID and SecretKey configured in GenerateTestUserSig.
/// No automatic account login, welcome message or business backend.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let navigation = UINavigationController()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // S05: palette and light/dark mode are independent. First launch keeps the brand dark look;
        // afterwards the stored choice is applied to both theme stores (AtomicX + TUIChatKit).
        DemoLoginStore.initialize()
        DemoGroupDiagnostics.onFailure = { operation, result in
            HostDiagnostics.record("group.\(operation)", code: result.code, message: result.desc)
        }
        DemoThemeCoordinator.bridges = [DemoChatThemeBridge()]
        DemoLanguage.onSync = { LanguageHelper.saveLanguage($0) }
        HomeKit.install(dataSource: DemoHomeDataSource(), actions: DemoHomeActions())
        MineKit.install(dataSource: DemoMineDataSource(), actions: DemoMineActions())
        DemoThemeCoordinator.bootstrap()
        DemoLanguage.syncUIKit()
        DemoChat.registerRenderersOnce()
        DemoCallGift.install()
        DemoSessionWatcher.shared.install()
        HostNavigationTransition.install(on: navigation)
        return true
    }

    /// iOS 27 requires the scene life cycle (an app without it is terminated at launch): the window is created when the
    /// scene connects, one-time setup stays in `didFinishLaunching`.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// Builds the window of the first scene (the app is single-window: `UIApplicationSupportsMultipleScenes` is off)
    /// and shows the login page.
    fileprivate func installWindow(in windowScene: UIWindowScene) {
        guard window == nil else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        navigation.viewControllers = [LoginViewController(resuming: LoginViewController.hasResumableLogin)]
        window.rootViewController = navigation
        DemoThemeCoordinator.applyWindowStyle(window)
        window.makeKeyAndVisible()
        DispatchQueue.main.async {
            (self.navigation.viewControllers.first as? LoginViewController)?.autoLoginIfSaved()
        }
    }

    /// Opens a 1v1 chat on the Messages tab of the signed-in host (e.g. from an in-app message banner).
    func openChat(userID: String, title: String? = nil) {
        (navigation.viewControllers.first as? MainViewController)?.openChat(userID: userID, title: title)
    }

    /// Back to a fresh login page after 退出登录; the saved login is dropped so the field starts empty and nothing auto-signs in.
    func showLogin(afterLogout: Bool = false, notice: String? = nil) {
        if afterLogout { DemoLoginStore.clear() }
        if notice != nil, navigation.presentedViewController != nil {
            navigation.dismiss(animated: false)
        }
        navigation.setViewControllers([LoginViewController()], animated: true)
        guard let notice else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            SocialToast.show(notice, kind: .error, duration: .long)
        }
    }
}

/// Owns the app window (scene life cycle, required since iOS 27); the root controller is built by `AppDelegate`.
@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.installWindow(in: windowScene)
        window = appDelegate.window
    }
}
