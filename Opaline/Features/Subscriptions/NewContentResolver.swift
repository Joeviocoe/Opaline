import Foundation

/// Decides which subscribed channels get a "new video" dot
/// (issue #13). A channel qualifies when its public RSS feed has a
/// video published within `windowDays` that isn't in watch history;
/// watching ANY of the channel's recent videos clears the dot
/// (semantics confirmed by the issue reporter).
enum NewContentResolver {
    static let windowDays = 7

    static func channelsWithNewContent(
        uploadsByChannel: [String: [RSSVideoEntry]],
        watchedVideoIds: Set<String>,
        now: Date = Date()
    ) -> Set<String> {
        let cutoff = now.addingTimeInterval(
            -Double(NewContentResolver.windowDays) * 86_400
        )
        var result: Set<String> = []
        for (channelId, entries) in uploadsByChannel {
            let recent = entries.filter { $0.published >= cutoff }
            guard !recent.isEmpty else {
                continue
            }
            let hasWatchedRecent = recent.contains {
                watchedVideoIds.contains($0.videoId)
            }
            if !hasWatchedRecent {
                result.insert(channelId)
            }
        }
        return result
    }
}
