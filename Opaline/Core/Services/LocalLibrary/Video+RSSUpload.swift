import Foundation

extension Video {
    /// A feed card built from one Atom entry plus the channel it came from.
    ///
    /// RSS cannot supply duration, live status, or feedback actions, and its
    /// avatar comes from the local subscription record rather than the feed
    /// — which is exactly why identity is captured at subscribe time.
    /// `VideoCardHelper.configureBadges` already hides the duration badge
    /// when it is nil, so the card degrades to a clean thumbnail corner
    /// rather than breaking its layout.
    init(rssEntry: RSSVideoEntry, channel: SubscribedChannel) {
        self.init(
            id: rssEntry.videoId,
            title: rssEntry.title,
            channelId: channel.id,
            channelName: channel.title,
            channelAvatarURL: channel.avatarURL,
            thumbnailURL: AppURLs.YouTube.thumbnailURL(
                videoId: rssEntry.videoId
            ),
            viewCount: rssEntry.viewCount.map {
                VideoFormatters.formatViewCount($0)
            },
            publishedAt: VideoFormatters.formatRelativeDate(
                rssEntry.published
            ),
            duration: nil,
            isLive: false
        )
    }
}
