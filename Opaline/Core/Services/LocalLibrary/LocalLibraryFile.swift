import Foundation

/// What came back from reading a store file. `empty` and `unreadable` are
/// deliberately different cases: only the first is safe to overwrite. A
/// store that treats an undecodable file as an empty one destroys the
/// user's only copy of their library on the very next write — which is what
/// `AppNotificationStore.loadIfNeeded` does today, and what this exists to
/// avoid inheriting.
enum LocalLibraryLoad<Item> {
    case empty
    case loaded([Item])
    case unreadable(String)
}

/// The versioned envelope every local-library file is wrapped in. Reading a
/// file whose version is *newer* than this build understands must not be
/// treated as corruption either — an older build should leave a newer
/// file alone rather than truncate it to whatever it can parse.
struct LocalLibraryEnvelope<Item: Codable>: Codable {
    let version: Int
    let items: [Item]
}

/// Shared disk layer for the local library: `Application Support/LocalLibrary/`.
///
/// Not `Caches` (iOS purges it under storage pressure) and not
/// `UserDefaults` (a whole plist rewritten per video watched is the wrong
/// durability class). Unlike `DownloadStore` this is deliberately *not*
/// excluded from backup: it is small, it is the user's own data, and it is
/// the one thing here that cannot be re-downloaded.
enum LocalLibraryFile {
    /// Bump only for a change an older build could not read correctly.
    /// Additive fields do not need it — the models decode tolerantly.
    static let currentVersion = 1

    private static let directoryName = "LocalLibrary"

    static func url(for fileName: String) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true
        )
        return base.appendingPathComponent(fileName)
    }

    static func load<Item: Codable>(
        _ type: Item.Type,
        fileName: String
    ) -> LocalLibraryLoad<Item> {
        let fileURL = url(for: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            AppLog.library("load \(fileName): empty (no file)")
            return .empty
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLog.library("load \(fileName): UNREADABLE (cannot read file)")
            return .unreadable("unreadable file")
        }
        return decode(type, data: data, fileName: fileName)
    }

    /// Returns false when the write did not happen, so a caller can keep its
    /// in-memory copy authoritative rather than believing it persisted.
    @discardableResult
    static func save<Item: Codable>(
        _ items: [Item],
        fileName: String
    ) -> Bool {
        let envelope = LocalLibraryEnvelope(
            version: currentVersion, items: items
        )
        guard let data = try? JSONEncoder().encode(envelope) else {
            AppLog.library("save \(fileName): FAILED to encode")
            return false
        }
        let started = Date()
        do {
            // The same protection `AppNotificationStore` uses: a background
            // wake on a locked device must still be able to write, or the
            // entry is silently lost exactly when it matters.
            try data.write(
                to: url(for: fileName),
                options: [
                    .atomic,
                    .completeFileProtectionUntilFirstUserAuthentication
                ]
            )
        } catch {
            AppLog.library("save \(fileName): FAILED \(error)")
            return false
        }
        let ms = Int(Date().timeIntervalSince(started) * 1_000)
        AppLog.library(
            "save \(fileName): \(items.count) items"
                + " \(data.count)b in \(ms)ms"
        )
        return true
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
        AppLog.library("delete \(fileName)")
    }

    private static func decode<Item: Codable>(
        _ type: Item.Type,
        data: Data,
        fileName: String
    ) -> LocalLibraryLoad<Item> {
        guard data.count > 0 else {
            AppLog.library("load \(fileName): empty (zero bytes)")
            return .empty
        }
        let decoded = try? JSONDecoder().decode(
            LocalLibraryEnvelope<Item>.self, from: data
        )
        guard let envelope = decoded else {
            AppLog.library(
                "load \(fileName): UNREADABLE (decode failed,"
                    + " \(data.count)b) — file preserved"
            )
            return .unreadable("decode failed")
        }
        guard envelope.version <= currentVersion else {
            AppLog.library(
                "load \(fileName): UNREADABLE (version"
                    + " \(envelope.version) > \(currentVersion))"
                    + " — file preserved"
            )
            return .unreadable("newer version \(envelope.version)")
        }
        AppLog.library(
            "load \(fileName): loaded \(envelope.items.count) items"
                + " v\(envelope.version) \(data.count)b"
        )
        return .loaded(envelope.items)
    }
}
