import CommonCrypto
import CryptoKit
import Foundation

/// Encrypted backup container.
///
/// Layout (all integers big-endian):
/// ```
/// 0   8   magic "CHRTKBK1"
/// 8   1   container version (1)
/// 9   1   KDF id (1 = PBKDF2-HMAC-SHA256)
/// 10  4   KDF iterations
/// 14  16  salt
/// 30  …   AES-256-GCM combined box (12-byte nonce ‖ ciphertext ‖ 16-byte tag)
/// ```
/// The 30-byte header is authenticated as associated data, so tampering with it fails decryption.
enum BackupCrypto {
    static let magic = Array("CHRTKBK1".utf8)
    static let containerVersion: UInt8 = 1
    static let kdfPBKDF2SHA256: UInt8 = 1
    static let defaultIterations: UInt32 = 600_000
    static let minimumIterations: UInt32 = 100_000
    static let saltLength = 16
    static let headerLength = 30
    static let minimumPasswordLength = 8

    static func normalize(_ password: String) -> [UInt8] {
        Array(password.precomposedStringWithCanonicalMapping.utf8)
    }

    static func deriveKey(password: String, salt: [UInt8], iterations: UInt32) throws -> SymmetricKey {
        let pw = normalize(password)
        var derived = [UInt8](repeating: 0, count: 32)
        let pwChars = pw.map { CChar(bitPattern: $0) }
        let status = derived.withUnsafeMutableBufferPointer { out in
            salt.withUnsafeBufferPointer { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwChars, pwChars.count,
                    saltPtr.baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    out.baseAddress, 32
                )
            }
        }
        guard status == Int32(kCCSuccess) else { throw DomainError.backupCorrupted }
        return SymmetricKey(data: derived)
    }

    static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "secure random generator failed")
        return bytes
    }

    static func header(iterations: UInt32, salt: [UInt8]) -> [UInt8] {
        var h = magic
        h.append(containerVersion)
        h.append(kdfPBKDF2SHA256)
        h.append(UInt8((iterations >> 24) & 0xFF))
        h.append(UInt8((iterations >> 16) & 0xFF))
        h.append(UInt8((iterations >> 8) & 0xFF))
        h.append(UInt8(iterations & 0xFF))
        h.append(contentsOf: salt)
        return h
    }

    static func encrypt(_ plaintext: Data, password: String, iterations: UInt32 = defaultIterations) throws -> Data {
        guard password.count >= minimumPasswordLength else { throw DomainError.passwordTooShort }
        let salt = randomBytes(saltLength)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let head = header(iterations: iterations, salt: salt)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Data(head))
        guard let combined = box.combined else { throw DomainError.backupCorrupted }
        return Data(head) + combined
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > headerLength + 28, Array(bytes[0..<8]) == magic else { throw DomainError.backupCorrupted }
        guard bytes[8] == containerVersion else { throw DomainError.backupUnsupportedVersion(Int(bytes[8])) }
        guard bytes[9] == kdfPBKDF2SHA256 else { throw DomainError.backupCorrupted }
        let iterations = (UInt32(bytes[10]) << 24) | (UInt32(bytes[11]) << 16) | (UInt32(bytes[12]) << 8) | UInt32(bytes[13])
        // Reject absurd iteration counts (corrupt header or a denial-of-service file).
        guard iterations >= 1_000, iterations <= 10_000_000 else { throw DomainError.backupCorrupted }
        let salt = Array(bytes[14..<30])
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            return try AES.GCM.open(box, using: key, authenticating: Data(bytes[0..<headerLength]))
        } catch {
            throw DomainError.backupWrongPassword
        }
    }
}
