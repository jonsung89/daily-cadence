import CryptoKit
import Foundation
import Testing
@testable import DailyCadence

/// Verifies the nonce pair we send through Sign in with Apple. The raw
/// half goes to Supabase; the hashed half goes to Apple. Supabase
/// re-hashes raw and compares against the `nonce` claim — so the contract
/// here is "hashed must equal SHA-256(raw)" and "raw must be sufficiently
/// random."
struct AppleSignInNonceTests {

    @Test func hashedIsSha256OfRaw() {
        let nonce = AppleSignInNonce.make()
        let recomputed = SHA256.hash(data: Data(nonce.raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(nonce.hashed == recomputed)
    }

    @Test func rawIsRequestedLength() {
        let nonce = AppleSignInNonce.make(length: 48)
        #expect(nonce.raw.count == 48)
    }

    @Test func consecutiveNoncesDiffer() {
        let a = AppleSignInNonce.make()
        let b = AppleSignInNonce.make()
        #expect(a.raw != b.raw)
        #expect(a.hashed != b.hashed)
    }

    @Test func hashedIs64HexChars() {
        let nonce = AppleSignInNonce.make()
        #expect(nonce.hashed.count == 64)
        #expect(nonce.hashed.allSatisfy { $0.isHexDigit })
    }
}
