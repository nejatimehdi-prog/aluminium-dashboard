import Foundation
import SwiftData

enum PersistenceController {
    static let storeName = "Chortkeh.store"

    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Chortkeh", isDirectory: true)
    }

    /// Creates the on-device container. The store directory is excluded from iCloud/iTunes backup
    /// (the user makes explicit encrypted backups instead) and protected with iOS Data Protection.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, migrationPlan: ChortkehMigrationPlan.self, configurations: [config])
        }
        let fm = FileManager.default
        var dir = storeDirectory
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        let url = dir.appendingPathComponent(storeName)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: ChortkehMigrationPlan.self, configurations: [config])
        applyFileProtection()
        return container
    }

    /// Re-applies protection to the store files (SQLite creates -wal / -shm siblings lazily).
    static func applyFileProtection() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        }
    }
}
