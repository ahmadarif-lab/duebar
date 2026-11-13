import CommonCrypto
import Foundation

/// A salted PBKDF2 hash of a password: enough to check a password later without storing it.
public struct PasswordVerifier: Codable, Equatable, Sendable {
    public var salt: Data
    public var hash: Data
    public var iterations: Int

    public static let defaultIterations = 600_000

    public init(salt: Data, hash: Data, iterations: Int) {
        self.salt = salt
        self.hash = hash
        self.iterations = iterations
    }

    public static func make(password: String, iterations: Int = defaultIterations) -> PasswordVerifier {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        precondition(status == errSecSuccess, "no random bytes")
        return PasswordVerifier(salt: salt, hash: derive(password, salt: salt, iterations: iterations), iterations: iterations)
    }

    public func matches(_ password: String) -> Bool {
        let candidate = Self.derive(password, salt: salt, iterations: iterations)
        // Compare every byte, so timing doesn't reveal how much of the hash was right.
        guard candidate.count == hash.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate, hash) { diff |= a ^ b }
        return diff == 0
    }

    private static func derive(_ password: String, salt: Data, iterations: Int) -> Data {
        var out = Data(count: 32)
        let pw = Array(password.precomposedStringWithCanonicalMapping.utf8)
        let status = out.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                pw.withUnsafeBufferPointer { pwBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        UnsafeRawPointer(pwBytes.baseAddress ?? UnsafePointer(bitPattern: 1)!).assumingMemoryBound(to: Int8.self), pw.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        outBytes.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        precondition(status == kCCSuccess, "pbkdf2 failed")
        return out
    }
}
