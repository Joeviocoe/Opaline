import Foundation

/// One video watched on this device, with no account.
///
/// `viewCount` and `publishedAt` are stored **as the strings that were
/// displayed**, not as numbers or dates: they are already formatted by the
/// time a `Video` exists, and storing a raw count would reintroduce the
/// 32-bit narrowing problem this port keeps running into on armv7.
/// `watchedAt` is a `Date` (Codable writes it as a Double) — never `Int`
/// epoch seconds, for the same reason.
struct LocalHistoryEntry: Codable {
    let videoId: String
    let title: String
    let channelId: String?
    let channelName: String
    let channelAvatarURL: String?
    let thumbnailURL: String
    let duration: String?
    let viewCount: String?
    let publishedAt: String?
    let isShort: Bool
    let watchedAt: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try container.decode(String.self, forKey: .videoId)
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        channelId = try container.decodeIfPresent(
            String.self, forKey: .channelId
        )
        channelName = try container.decodeIfPresent(
            String.self, forKey: .channelName
        ) ?? ""
        channelAvatarURL = try container.decodeIfPresent(
            String.self, forKey: .channelAvatarURL
        )
        thumbnailURL = try container.decodeIfPresent(
            String.self, forKey: .thumbnailURL
        ) ?? ""
        duration = try container.decodeIfPresent(
            String.self, forKey: .duration
        )
        viewCount = try container.decodeIfPresent(
            String.self, forKey: .viewCount
        )
        publishedAt = try container.decodeIfPresent(
            String.self, forKey: .publishedAt
        )
        isShort = try container.decodeIfPresent(
            Bool.self, forKey: .isShort
        ) ?? false
        watchedAt = try container.decodeIfPresent(
            Date.self, forKey: .watchedAt
        ) ?? Date()
    }

    init(video: Video, watchedAt: Date = Date()) {
        videoId = video.id
        title = video.title
        channelId = video.channelId
        channelName = video.channelName
        channelAvatarURL = video.channelAvatarURL
        thumbnailURL = video.thumbnailURL
        duration = video.duration
        viewCount = video.viewCount
        publishedAt = video.publishedAt
        isShort = video.isShort
        self.watchedAt = watchedAt
    }

    /// `feedbackActions` stays empty on purpose: those are opaque
    /// server-issued tokens, and a local entry has none — which is exactly
    /// why the History screen branches rather than pretending otherwise.
    var video: Video {
        Video(
            id: videoId,
            title: title,
            channelId: channelId,
            channelName: channelName,
            channelAvatarURL: channelAvatarURL,
            thumbnailURL: thumbnailURL,
            viewCount: viewCount,
            publishedAt: publishedAt,
            duration: duration,
            isShort: isShort
        )
    }
}
