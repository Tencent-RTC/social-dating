import Foundation
import UIKit

/// Host-app copy lookup. Every fixed UI string of the demo host lives in `Resources/Localization/*.lproj`
/// (same keys as the Android `res/values*`) and is read through here, so the language chosen on the login page
/// (`DemoLanguage`) applies everywhere. Customers can translate or reword a string by editing the .strings files only.
public enum DemoText {
    private static var cachedLanguage: String?
    private static var cachedBundles: [Bundle] = []
    private static let missing = "\u{0}"

    /// `%1$@`-style placeholders are filled from `args` in order.
    public static func get(_ key: String, _ args: String...) -> String {
        var format = key
        for bundle in bundles() {
            let value = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
            if value != missing {
                format = value
                break
            }
        }
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args.map { $0 as NSString })
    }

    /// Drops the cached bundles after the language changed or a module registered its resources.
    public static func invalidate() {
        cachedLanguage = nil
        cachedBundles = []
    }

    private static func bundles() -> [Bundle] {
        let language = DemoLanguage.resolved
        let sources = [Bundle.main] + HostResources.bundles
        if !cachedBundles.isEmpty, cachedLanguage == language, cachedBundles.count == sources.count { return cachedBundles }
        let folder: String
        switch language {
        case DemoLanguage.zhTW: folder = "zh-Hant"
        case DemoLanguage.en: folder = "en"
        default: folder = "zh-Hans"
        }
        cachedBundles = sources.map { source in
            source.path(forResource: folder, ofType: "lproj").flatMap { Bundle(path: $0) } ?? source
        }
        cachedLanguage = language
        return cachedBundles
    }
}

/// Display language of the login page (Ardot board K: L1 / L4 / L6). Only the login page host copy is
/// translated so far; the other host screens stay Simplified Chinese. The choice is stored locally.
public enum DemoLanguage {
    public static let system = "system"
    public static let zhCN = "zh-CN"
    public static let zhTW = "zh-TW"
    public static let en = "en"
    private static let key = "demo.loginLanguage"
    public static let didChange = Notification.Name("demo.language.didChange")
    public static var onSync: ((String) -> Void)?

    public static var choice: String {
        get { UserDefaults.standard.string(forKey: key) ?? zhCN }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            syncUIKit()
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    public static func syncUIKit() {
        let code: String
        switch resolved {
        case zhTW: code = "zh-Hant"
        case en: code = "en"
        default: code = "zh-Hans"
        }
        onSync?(code)
        DemoText.invalidate()
    }

    /// Resolved display language: zh-CN, zh-TW or en (any other system language falls back to English).
    public static var resolved: String {
        guard choice == system else { return choice }
        let first = Locale.preferredLanguages.first ?? "en"
        if first.hasPrefix("zh") {
            return (first.contains("Hant") || first.contains("TW") || first.contains("HK") || first.contains("MO")) ? zhTW : zhCN
        }
        return en
    }
}

public enum HostResources {
    private static var registered: [String: Bundle] = [:]
    private static var order: [Bundle] = []
    private static let lock = NSLock()

    public static let baseBundleName = "TUIHostBaseBundle"

    public static func register(bundleName: String, anchor: AnyClass? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard registered[bundleName] == nil, let bundle = locate(bundleName, anchor: anchor) else { return }
        registered[bundleName] = bundle
        order.append(bundle)
        DemoText.invalidate()
    }

    public static var bundles: [Bundle] {
        lock.lock()
        defer { lock.unlock() }
        if registered[baseBundleName] == nil, let bundle = locate(baseBundleName, anchor: HostBundleAnchor.self) {
            registered[baseBundleName] = bundle
            order.insert(bundle, at: 0)
        }
        return order
    }

    private static func locate(_ name: String, anchor: AnyClass?) -> Bundle? {
        var roots = [Bundle.main]
        if let anchor { roots.append(Bundle(for: anchor)) }
        for root in roots {
            if let url = root.url(forResource: name, withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }
}

private final class HostBundleAnchor {}
