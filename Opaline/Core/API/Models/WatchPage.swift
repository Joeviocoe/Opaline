import Foundation

// MARK: - The screen around a video

/// Codable so a downloaded video can keep its page on disk: the in-memory
/// cache does not survive a relaunch, which is exactly when an offline video
/// is opened.
struct WatchPage: Codable {
    /// No raw values: a `CodingKey` derives them from the case names, and
    /// `servedOffline` is absent on purpose.
    private enum CodingKeys: CodingKey {
        case video, description, channelInfo, subscribeButtonText
        case isSubscribed, relatedVideos, likeCount, likeStatus
        case commentCount, nextVideo, playlistTitle, playlistVideos
    }

    let video: Video
    let description: String?
    let channelInfo: ChannelInfo?
    let subscribeButtonText: String?
    let isSubscribed: Bool
    let relatedVideos: [Video]
    let likeCount: String?
    let likeStatus: LikeStatus?
    /// Total comments as the server formats it ("13K") — the Shorts rail
    /// shows it without paying for a comments fetch.
    let commentCount: String?
    let nextVideo: Video?
    let playlistTitle: String?
    let playlistVideos: [Video]?
    /// Set when this page came off the disk instead of the network, so the
    /// rail below the video can say what it is actually listing. Left out of
    /// the coding keys deliberately: it describes how a page was delivered,
    /// not what it holds, and a stored page must decode without it.
    var servedOffline = false
}
