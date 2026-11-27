import UIKit
import AtomicX

/// One place that drives the theme stores. AtomicX is driven here; every other store (the Chat UIKit) is driven by a
/// registered bridge. Palette and light/dark mode are stored independently.
public protocol HostThemeBridge: AnyObject {
    func apply(mode: DemoThemeCoordinator.Mode, palette: String)
}

public enum DemoThemeCoordinator {
    public static let didChange = Notification.Name("demo.theme.didChange")

    public static var bridges: [HostThemeBridge] = []

    public enum Mode: String, CaseIterable {
        case system, light, dark
        public var title: String {
            switch self {
            case .system: return DemoText.get("demo_follow_system")
            case .light: return DemoText.get("demo_light")
            case .dark: return DemoText.get("demo_dark")
            }
        }
    }

    private static let modeKey = "demo.theme.mode"
    private static let paletteKey = "demo.theme.palette"

    public static var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .dark
    }

    public static var palette: String {
        let stored = UserDefaults.standard.string(forKey: paletteKey) ?? ""
        return SocialPalettes.info(stored) != nil ? stored : SocialPalettes.defaultKey
    }

    /// Called once at launch: pushes the stored (or default dark / violet) choice into both stores.
    public static func bootstrap() {
        push(mode: mode, palette: palette)
    }

    public static func setMode(_ mode: Mode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        push(mode: mode, palette: palette)
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { applyWindowStyle($0) }
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    public static func setPalette(_ key: String) {
        guard SocialPalettes.info(key) != nil else { return }
        UserDefaults.standard.set(key, forKey: paletteKey)
        push(mode: mode, palette: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    public static func applyWindowStyle(_ window: UIWindow?) {
        switch mode {
        case .system: window?.overrideUserInterfaceStyle = .unspecified
        case .light: window?.overrideUserInterfaceStyle = .light
        case .dark: window?.overrideUserInterfaceStyle = .dark
        }
    }

    private static func push(mode: Mode, palette: String) {
        let atomic: AtomicX.ThemeMode
        switch mode {
        case .system: atomic = .system
        case .light: atomic = .light
        case .dark: atomic = .dark
        }
        ThemeStore.shared.setMode(atomic)
        ThemeStore.shared.setPalette(palette)
        bridges.forEach { $0.apply(mode: mode, palette: palette) }
    }
}
