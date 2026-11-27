import UIKit

final class ChatBackgroundStore {
    static let shared = ChatBackgroundStore()

    static let didChangeNotification = Notification.Name("ChatBackgroundDidChangeNotification")

    static let conversationIDUserInfoKey = "conversationID"

    private static let keyPrefix = "chat_background::"

    private let defaults = UserDefaults.standard

    func imageURI(forConversationID conversationID: String) -> String? {
        return normalize(defaults.string(forKey: Self.keyPrefix + conversationID))
    }

    func setImageURI(_ uri: String?, forConversationID conversationID: String) {
        let key = Self.keyPrefix + conversationID
        if let normalized = normalize(uri) {
            defaults.set(normalized, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.conversationIDUserInfoKey: conversationID]
        )
    }

    private init() {}

    private func normalize(_ uri: String?) -> String? {
        guard let trimmed = uri?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct ChatBackgroundPresetItem {
    let imageURI: String?
    let thumbnailURI: String?
    /// Localized-string key of the name drawn over the thumbnail; nil for the 「默认」 cell.
    let nameKey: String?

    init(imageURI: String?, thumbnailURI: String?, nameKey: String? = nil) {
        self.imageURI = imageURI
        self.thumbnailURI = thumbnailURI
        self.nameKey = nameKey
    }

    var isDefault: Bool {
        return imageURI == nil
    }
}

/// The eight preset chat backgrounds shipped in the app bundle (`chat_bg_<id>` 1080x2340, `chat_bg_thumb_<id>` 288x624).
/// A chosen preset is stored as `preset://<id>`; older stored values (SDK online images, custom URLs) still load
/// through Kingfisher because only the `preset://` scheme is handled locally.
enum ChatBackgroundPresetProvider {

    private static let scheme = "preset://"

    /// Dark four first, then the light four; the order is the order in the picker.
    private static let darkIDs = ["night", "heart", "neon", "still"]
    private static let lightIDs = ["breeze", "mint", "peach", "salt"]

    static func presetItems() -> [ChatBackgroundPresetItem] {
        var items = [ChatBackgroundPresetItem(imageURI: nil, thumbnailURI: nil)]
        for id in darkIDs + lightIDs {
            items.append(ChatBackgroundPresetItem(
                imageURI: scheme + id,
                thumbnailURI: scheme + id,
                nameKey: "ChatBackgroundPreset" + id.prefix(1).uppercased() + id.dropFirst()
            ))
        }
        return items
    }

    static func presetID(of uri: String) -> String? {
        return uri.hasPrefix(scheme) ? String(uri.dropFirst(scheme.count)) : nil
    }

    /// Full-size bundled image for a `preset://` value; nil for anything else.
    static func fullImage(for uri: String) -> UIImage? {
        guard let id = presetID(of: uri) else { return nil }
        return AtomicXChatResources.image(named: "chat_bg_\(id)")
    }

    static func thumbnailImage(for uri: String) -> UIImage? {
        guard let id = presetID(of: uri) else { return nil }
        return AtomicXChatResources.image(named: "chat_bg_thumb_\(id)")
    }

    /// True for the light-coloured presets, which get a dark scrim while the UI is in dark mode.
    static func isLightPreset(_ uri: String) -> Bool {
        guard let id = presetID(of: uri) else { return false }
        return lightIDs.contains(id)
    }
}
