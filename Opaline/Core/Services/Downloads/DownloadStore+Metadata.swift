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

// MARK: - The page around the video

extension DownloadStore {
    private static let pageFileName = "page.json"
    private static let segmentsFileName = "sponsorblock.json"
    private static let avatarFileName = "avatar.jpg"
    private static let votesFileName = "votes.json"

    static func savePage(_ page: WatchPage, for videoId: String) {
        write(
            page,
            to: folder(for: videoId).appendingPathComponent(pageFileName),
            what: "page"
        )
    }

    static func page(for videoId: String) -> WatchPage? {
        read(
            WatchPage.self,
            from: folder(for: videoId).appendingPathComponent(pageFileName)
        )
    }

    static func saveSegments(
        _ segments: [SponsorBlockSegment],
        for videoId: String
    ) {
        write(
            segments,
            to: folder(for: videoId).appendingPathComponent(segmentsFileName),
            what: "segments"
        )
    }

    static func segments(for videoId: String) -> [SponsorBlockSegment]? {
        read(
            [SponsorBlockSegment].self,
            from: folder(for: videoId).appendingPathComponent(segmentsFileName)
        )
    }

    static func saveVotes(_ votes: RYDVotes, for videoId: String) {
        write(
            votes,
            to: folder(for: videoId).appendingPathComponent(votesFileName),
            what: "votes"
        )
    }

    static func votes(for videoId: String) -> RYDVotes? {
        read(
            RYDVotes.self,
            from: folder(for: videoId).appendingPathComponent(votesFileName)
        )
    }

    /// The channel picture, kept and re-primed exactly like the thumbnail.
    static func saveAvatar(_ data: Data, for videoId: String, url: URL) {
        try? data.write(
            to: folder(for: videoId).appendingPathComponent(avatarFileName),
            options: .atomic
        )
        ThumbnailLoader.shared.diskCache.store(data: data, for: url)
    }

    /// Hands the stored channel picture back to the image cache, if the page
    /// names one — the offline screen asks for it by URL like any other.
    static func primeAvatarIfPossible(from page: WatchPage, videoId: String) {
        guard let raw = page.channelInfo?.avatarURL
            ?? page.video.channelAvatarURL,
            let url = URL(string: raw) else {
            return
        }
        primeAvatar(for: videoId, url: url)
    }

    static func primeAvatar(for videoId: String, url: URL) {
        guard let data = try? Data(contentsOf: folder(for: videoId)
            .appendingPathComponent(avatarFileName)) else {
            return
        }
        ThumbnailLoader.shared.diskCache.store(data: data, for: url)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL, what: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            AppLog.downloads("could not encode \(what) for \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
