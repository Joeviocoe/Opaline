import Foundation

// MARK: - Showing a walk while it runs
//
// A walk takes a dozen seconds or more, and a channel that answered early
// has no reason to wait on one that answers late. Each partial page is the
// channels answered so far laid over the last complete walk, so the list
// updates channel by channel instead of either collapsing to the first
// channel back or sitting still until the end.

extension LocalSubscriptionFeedService {
    /// What the walk has so far, over the baseline for everything it has not
    /// reached yet. A pull-to-refresh drops the per-channel cache, so without
    /// the baseline its first partial page would be one channel long.
    func partialPage(
        _ partial: [String: [Video]],
        channels: [SubscribedChannel]
    ) -> FeedPage {
        let merged = baselineUploads.merging(partial) { _, fresh in fresh }
        return assemble(uploads: merged, channels: channels, final: false)
    }

    /// Merges rather than replaces: a channel that failed this walk keeps
    /// what it had, the same rule `LocalChannelActivity.record` applies.
    func rememberBaseline(_ byChannel: [String: [Video]]) {
        baselineUploads.merge(byChannel) { _, fresh in fresh }
    }

    /// On launch the screen paints from the disk cache before any walk has
    /// run, so that page is the baseline until one does. Grouped back by
    /// channel, which is the shape the walk reports in.
    func seedBaseline(from page: FeedPage) {
        guard baselineUploads.isEmpty else {
            return
        }
        var grouped: [String: [Video]] = [:]
        for video in page.videos {
            guard let channelId = video.channelId else {
                continue
            }
            grouped[channelId, default: []].append(video)
        }
        baselineUploads = grouped
        AppLog.library(
            "local feed: baseline seeded from cache, \(grouped.count) channels"
        )
    }
}
