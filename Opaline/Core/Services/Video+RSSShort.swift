import Foundation

extension Video {
    /// A card built from its channel's Atom entry. The feed gives everything
    /// a card shows except the duration and live status; the poster is
    /// derived from the video id.
    ///
    /// `isShort` cannot be inferred from the feed — Atom says nothing about
    /// short-form — so the caller states it: the `UUSH` playlist feed is
    /// shorts by definition, the long-form and full feeds are not.
    init(
        rssEntry entry: RSSVideoEntry,
        channel: SubscribedChannel,
        isShort: Bool
    ) {
        self.init(
            id: entry.videoId,
            title: entry.title,
            channelId: channel.id,
            channelName: channel.title,
            channelAvatarURL: channel.avatarURL,
            thumbnailURL: AppURLs.YouTube.thumbnailURL(
                videoId: entry.videoId
            ),
            viewCount: entry.viewCount.map {
                VideoFormatters.formatViewCount($0)
            },
            publishedAt: VideoFormatters.formatRelativeDate(entry.published),
            duration: nil,
            isShort: isShort
        )
    }

    /// A short, from the channel's `UUSH` feed.
    init(short entry: RSSVideoEntry, channel: SubscribedChannel) {
        self.init(rssEntry: entry, channel: channel, isShort: true)
    }
}
