import UIKit

/// Bookkeeping for the lazy related-channel fetches. `inFlight` is not
/// reset on a video switch on purpose — the outstanding completions still
/// decrement it, so zeroing it here would drive it negative.
struct ChannelFetchQueue {
    var pending: [String] = []
    var inFlight = 0
    var requested: Set<String> = []
}

/// Paging sizes for the two lazily-revealed lists on the watch screen.
enum WatchPaging {
    static let relatedBatch = 5
    static let commentsPage = 10
}

/// Memoizes the last `applyDescriptionText()` output so repeat calls with
/// the same text and theme reuse it instead of re-running `LinkifiedText`.
struct DescriptionAttributedCache {
    let text: String
    let isDark: Bool
    let attributed: NSAttributedString
}
