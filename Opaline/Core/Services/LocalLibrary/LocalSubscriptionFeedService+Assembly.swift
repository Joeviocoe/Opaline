import Foundation

// MARK: - Turning fetched tabs into a feed
//
// Split out because both of these are pure functions of what came back off
// the wire — they touch none of the service's state — and keeping them here
// is what holds the service itself under the file and function limits.

extension LocalSubscriptionFeedService {
    /// Every fetched video paired with the keys the order depends on.
    ///
    /// The date is approximate by necessity: a tab dates a video with
    /// `publishedTimeText` ("3 hours ago"), so everything inside an hour
    /// shares one value. `channelRank` and `positionInChannel` are what make
    /// the resulting ties resolvable — see `LocalFeedOrder`. `channelRank`
    /// comes from the subscription list rather than the uploads dictionary
    /// precisely because dictionary order is not stable across launches.
    func feedEntries(
        uploads: [String: [Video]],
        channels: [SubscribedChannel]
    ) -> [LocalFeedOrder.Entry] {
        var entries: [LocalFeedOrder.Entry] = []
        for (rank, channel) in channels.enumerated() {
            guard let videos = uploads[channel.id] else {
                continue
            }
            let fallback = newestDate(in: videos)
            for (position, video) in videos.enumerated() {
                entries.append(
                    LocalFeedOrder.Entry(
                        video: withOwner(video, channel: channel),
                        date: date(for: video, position: position,
                                   fallback: fallback),
                        channelRank: rank,
                        positionInChannel: position
                    )
                )
            }
        }
        return entries
    }

    /// The newest date this channel's videos could be dated to, used to place
    /// the ones that have no date at all.
    private func newestDate(in videos: [Video]) -> Date? {
        videos.compactMap { video in
            video.publishedAt
                .flatMap { VideoFormatters.approximateDate(fromRelative: $0) }
        }.max()
    }

    /// **Shorts carry no publish date.** `parseReelItem` sets `publishedAt`
    /// to nil, because the Shorts tab simply does not include the field —
    /// there is no relative text to approximate from.
    ///
    /// Treating that as "very old" is what made the Shorts switch look
    /// broken: they were fetched, parsed, and then dropped wholesale by the
    /// 30-day window before anything could show them. Undated is *unknown*,
    /// not old.
    ///
    /// So an undated video is placed at its channel's most recent upload,
    /// nudged back a second per position. It keeps the channel's own
    /// newest-first order, sits just below that channel's dated videos
    /// rather than above them, and survives the window — which is the whole
    /// point. It is a guess, but every possible placement is a guess when
    /// the field does not exist, and "alongside that channel's recent
    /// activity" is the one that behaves sensibly.
    private func date(
        for video: Video, position: Int, fallback: Date?
    ) -> Date {
        if let text = video.publishedAt,
           let exact = VideoFormatters.approximateDate(fromRelative: text) {
            return exact
        }
        guard let fallback = fallback else {
            // No dated video anywhere in this channel — a Shorts-only
            // channel. Anchor to now so it is not filtered away entirely.
            return Date().addingTimeInterval(-Double(position))
        }
        return fallback.addingTimeInterval(-Double(position + 1))
    }

    /// A tab's videos often omit the owner, since the response is already
    /// scoped to that channel. The cards need it to render a name and avatar,
    /// and the duration enrichment used to need `channelId` to group by.
    private func withOwner(
        _ video: Video, channel: SubscribedChannel
    ) -> Video {
        var copy = video
        if copy.channelId == nil {
            copy.channelId = channel.id
        }
        if copy.channelName.isEmpty {
            copy.channelName = channel.title
        }
        if copy.channelAvatarURL == nil {
            copy.channelAvatarURL = channel.avatarURL
        }
        return copy
    }

    /// The newest upload per channel, which is what orders the channel bar.
    /// Taken before the age window, so a channel that last posted two months
    /// ago still gets a real date and sorts above one that never posts.
    func latestUploads(
        in entries: [LocalFeedOrder.Entry]
    ) -> [String: Date] {
        var latest: [String: Date] = [:]
        for entry in entries {
            guard let channelId = entry.video.channelId else {
                continue
            }
            if let known = latest[channelId], known >= entry.date {
                continue
            }
            latest[channelId] = entry.date
        }
        return latest
    }
}
