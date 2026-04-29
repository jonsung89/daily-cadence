import CryptoKit
import Foundation
import Security

/// Generates the nonce pair used by Sign in with Apple → Supabase.
///
/// Apple's flow expects the request's `nonce` to be the **SHA-256 hex** of a
/// raw random string. The returned ID token embeds that hashed value as its
/// `nonce` claim. Supabase needs the **raw** value to re-hash and compare —
/// so we hold both, send `hashed` to Apple, and forward `raw` to Supabase.
struct AppleSignInNonce {
    let raw: String
    let hashed: String

    static func make(length: Int = 32) -> AppleSignInNonce {
        let raw = randomString(length: length)
        return AppleSignInNonce(raw: raw, hashed: sha256(raw))
    }

    private static let charset: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
    )

    private static func randomString(length: Int) -> String {
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            if Int(byte) < charset.count {
                result.append(charset[Int(byte)])
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
