import Foundation

public enum HostNotifyPrefs {
    public static let messageKey = "demo.notifyMessage"

    public static var messageAlerts: Bool {
        UserDefaults.standard.object(forKey: messageKey) as? Bool ?? true
    }
}

/// Error codes go to the log only; they are never shown to users.
public enum HostDiagnostics {
    public static var logger: (String) -> Void = { NSLog("Chat1v1: %@", $0) }

    public static func record(_ tag: String, code: Int = 0, message: String = "") {
        let codePart = code != 0 ? " code=\(code)" : ""
        let messagePart = message.isEmpty ? "" : " \(message)"
        logger("\(tag)\(codePart)\(messagePart)")
    }
}
