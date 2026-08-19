import Foundation

/// Where downloaded videos live on disk.
///
/// Application Support, not Caches: iOS purges Caches under storage pressure,
/// and a file the user explicitly asked to keep has to survive that. The whole
/// tree is excluded from iCloud backup — a few gigabytes of video has no
/// business in someone's backup quota.
enum DownloadStore {
    /// Posted whenever a download appears, finishes or is removed, so any
    /// screen showing download state can repaint without polling.
    static let didChangeNotification = Notification.Name(
        "DownloadStoreDidChange"
    )

    private static let folderName = "Downloads"
    private static let videoFileName = "video.mp4"
    /// What a half-finished transfer leaves behind. Named by suffix so that
    /// cleaning up after a job cannot reach the metadata stored beside it.
    static let partSuffix = ".part.mp4"

    static let root: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        var url = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    static func folder(for videoId: String) -> URL {
        root.appendingPathComponent(videoId, isDirectory: true)
    }

    /// The finished, playable file. Present only once the mux succeeded, so
    /// its existence is the one source of truth for "this is downloaded".
    static func videoFile(for videoId: String) -> URL {
        folder(for: videoId).appendingPathComponent(videoFileName)
    }

    static func partFile(for videoId: String, named name: String) -> URL {
        folder(for: videoId).appendingPathComponent(name)
    }

    /// A job that ended badly leaves this behind, so the row it belongs to
    /// can say so instead of sitting there looking unfinished forever.
    static func markFailed(_ videoId: String) {
        FileManager.default.createFile(
            atPath: failureFile(for: videoId).path, contents: nil
        )
    }

    static func clearFailure(_ videoId: String) {
        try? FileManager.default.removeItem(at: failureFile(for: videoId))
    }

    static func hasFailed(_ videoId: String) -> Bool {
        FileManager.default.fileExists(atPath: failureFile(for: videoId).path)
    }

    private static func failureFile(for videoId: String) -> URL {
        folder(for: videoId).appendingPathComponent("failed")
    }

    static func isDownloaded(_ videoId: String) -> Bool {
        FileManager.default.fileExists(atPath: videoFile(for: videoId).path)
    }

    static func downloadedIds() -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            atPath: root.path
        )
        return (contents ?? []).filter(isDownloaded)
    }

    @discardableResult
    static func prepareFolder(for videoId: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: folder(for: videoId), withIntermediateDirectories: true
            )
            return true
        } catch {
            AppLog.downloads("could not create folder for \(videoId): \(error)")
            return false
        }
    }

    static func remove(_ videoId: String) {
        try? FileManager.default.removeItem(at: folder(for: videoId))
        announceChange()
    }

    /// Drops the half-downloaded tracks — a cancelled or failed job must not
    /// strand hundreds of megabytes. Only the parts: everything else in the
    /// folder is the video and the metadata that describes it.
    static func removeParts(for videoId: String) {
        let folder = folder(for: videoId)
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: folder.path
        )) ?? []
        for name in names where name.hasSuffix(partSuffix) {
            try? FileManager.default.removeItem(
                at: folder.appendingPathComponent(name)
            )
        }
    }

    /// Always on the main thread: a job finishes on whatever queue the
    /// transport or the export session was running on, and every observer of
    /// this is UI. Posting from the export thread crashed the watch screen.
    static func announceChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: didChangeNotification, object: nil
            )
        }
    }
}
