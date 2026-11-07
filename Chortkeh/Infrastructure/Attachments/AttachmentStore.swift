import CryptoKit
import Foundation

/// Stores attachment images (e.g. cheque photos) encrypted with AES-GCM under a per-device key kept
/// in the Keychain, inside a directory with complete file protection. Nothing is uploaded anywhere.
final class AttachmentStore {
    static let keyAccount = "attachment-key-v1"
    let directory: URL
    private let key: SymmetricKey

    init(directory: URL? = nil, key: SymmetricKey? = nil) throws {
        let dir = directory ?? PersistenceController.storeDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.complete
        ])
        self.directory = dir
        if let key {
            self.key = key
        } else if let stored = KeychainStore.read(Self.keyAccount), stored.count == 32 {
            self.key = SymmetricKey(data: stored)
        } else {
            let fresh = SymmetricKey(size: .bits256)
            let raw = fresh.withUnsafeBytes { Data($0) }
            KeychainStore.write(raw, account: Self.keyAccount)
            self.key = fresh
        }
    }

    /// Saves plaintext `data` encrypted and returns nothing; the caller records `fileName` in the database.
    func save(_ data: Data, fileName: String) throws {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw DomainError.backupCorrupted }
        let url = directory.appendingPathComponent(fileName)
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func load(fileName: String) throws -> Data {
        let url = directory.appendingPathComponent(fileName)
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    func deleteAll() {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: file)
        }
    }
}
