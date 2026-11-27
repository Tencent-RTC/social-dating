import Foundation
import CryptoKit
import zlib

/// [DEMO_LOCAL_AUTH] Ephemeral result; the host does not persist or print UserSig.
struct LoginTicket {
    let sdkAppID: Int32
    let userID: String
    let userSig: String
}

enum LoginTicketError: Error {
    case missingConfiguration, invalidInput, compressionFailed
}

/// Uses HMAC-SHA256, zlib (not raw DEFLATE), and the original Tencent Base64 mapping.
enum GenerateTestUserSig {
    // Configure your Tencent Cloud SDKAppID and SecretKey before building.
    static let SDKAPPID: Int32
    static let SECRETKEY: String
    static let EXPIRETIME: Int64 = 604800

    static var isConfigured: Bool {
        SDKAPPID > 0 && !SECRETKEY.isEmpty && EXPIRETIME > 0
    }

    static func genTicket(userID: String) throws -> LoginTicket {
        let user = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { throw LoginTicketError.invalidInput }
        guard isConfigured else { throw LoginTicketError.missingConfiguration }
        let sig = try genTestUserSig(sdkAppID: SDKAPPID, userID: user, secretKey: SECRETKEY, expireSeconds: EXPIRETIME)
        return LoginTicket(sdkAppID: SDKAPPID, userID: user, userSig: sig)
    }

    static func genTestUserSig(
        sdkAppID: Int32, userID: String, secretKey: String,
        expireSeconds: Int64 = 604800,
        nowSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> String {
        guard sdkAppID > 0, !userID.isEmpty, !secretKey.isEmpty,
              expireSeconds > 0, nowSeconds > 0 else { throw LoginTicketError.invalidInput }
        let content = "TLS.identifier:\(userID)\nTLS.sdkappid:\(sdkAppID)\n" +
            "TLS.time:\(nowSeconds)\nTLS.expire:\(expireSeconds)\n"
        let authentication = HMAC<SHA256>.authenticationCode(
            for: Data(content.utf8), using: SymmetricKey(data: Data(secretKey.utf8))
        )
        let signature = Data(authentication).base64EncodedString()
        let doc: [String: Any] = [
            "TLS.ver": "2.0", "TLS.identifier": userID,
            "TLS.sdkappid": sdkAppID, "TLS.expire": expireSeconds,
            "TLS.time": nowSeconds, "TLS.sig": signature
        ]
        let input = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys])
        var length = compressBound(uLong(input.count))
        var buffer = [UInt8](repeating: 0, count: Int(length))
        let status = input.withUnsafeBytes { bytes in
            compress2(&buffer, &length, bytes.bindMemory(to: UInt8.self).baseAddress, uLong(input.count), Z_DEFAULT_COMPRESSION)
        }
        guard status == Z_OK else { throw LoginTicketError.compressionFailed }
        return Data(buffer.prefix(Int(length))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "*")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "=", with: "_")
    }
}
