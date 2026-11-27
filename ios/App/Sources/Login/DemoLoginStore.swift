import Foundation
import MMKV

struct SavedLogin {
    let sdkAppID: Int32
    let userID: String
}

enum DemoLoginStore {
    private static let storeID = "chat1v1_login"
    private static let sdkAppIDKey = "sdk_app_id"
    private static let userIDKey = "user_id"

    private static var store: MMKV?

    static func initialize() {
        MMKV.initialize(rootDir: nil)
        store = MMKV(mmapID: storeID)
    }

    static func save(sdkAppID: Int32, userID: String) {
        guard let store else { return }
        store.set(sdkAppID, forKey: sdkAppIDKey)
        store.set(userID, forKey: userIDKey)
    }

    static func load() -> SavedLogin? {
        guard let store else { return nil }
        let userID = store.string(forKey: userIDKey) ?? ""
        let sdkAppID = store.int32(forKey: sdkAppIDKey)
        guard !userID.isEmpty, sdkAppID > 0 else { return nil }
        return SavedLogin(sdkAppID: sdkAppID, userID: userID)
    }

    static func clear() {
        store?.clearAll()
    }
}
