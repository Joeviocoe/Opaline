import UIKit

// MARK: - What is stored next to the file

extension DownloadStore {
    private static let infoFileName = "info.json"
    private static let thumbFileName = "thumb.jpg"

    static func infoFile(for videoId: String) -> URL {
        folder(for: videoId).appendingPathComponent(infoFileName)
    }

    static func thumbFile(for videoId: String) -> URL {
        folder(for: videoId).appendingPathComponent(thumbFileName)
    }

    static func save(_ video: Video) {
        guard let data = try? JSONEncoder().encode(video) else {
            AppLog.downloads("could not encode metadata for \(video.id)")
            return
        }
        do {
            try data.write(to: infoFile(for: video.id), options: .atomic)
        } catch {
            AppLog.downloads("could not write metadata for \(video.id): \(error)")
        }
    }

    static func video(for videoId: String) -> Video? {
        guard let data = try? Data(contentsOf: infoFile(for: videoId)) else {
            return nil
        }
        return try? JSONDecoder().decode(Video.self, from: data)
    }

    /// Everything asked for, newest first — queued and failed included, not
    /// just what finished. The metadata is written the moment a download is
    /// requested, so a card appears immediately rather than minutes later.
    static func downloads() -> [Video] {
        let ids = (try? FileManager.default.contentsOfDirectory(
            atPath: root.path
        )) ?? []
        return ids
            .compactMap { id -> (Video, Date)? in
                guard let video = video(for: id) else {
                    return nil
                }
                return (video, requestedAt(id))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func requestedAt(_ videoId: String) -> Date {
        let values = try? infoFile(for: videoId)
            .resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    /// The thumbnail is kept beside the video and pushed back into the image
    /// cache on demand. The cache alone would not do: it lives in Caches, it
    /// expires, and a downloaded video has to still have a picture in a month
    /// with the network off.
    static func saveThumbnail(_ data: Data, for video: Video) {
        try? data.write(to: thumbFile(for: video.id), options: .atomic)
        primeThumbnail(for: video)
    }

    static func primeThumbnail(for video: Video) {
        guard let url = URL(string: video.thumbnailURL),
              let data = try? Data(contentsOf: thumbFile(for: video.id)) else {
            return
        }
        ThumbnailLoader.shared.diskCache.store(data: data, for: url)
    }
}
