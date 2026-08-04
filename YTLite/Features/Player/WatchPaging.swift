import UIKit

/// Portrait and landscape constraint sets for whichever view occupies the
/// slot below the description. The related list and the comments table swap
/// in and out of that one slot, so they carry identical bookkeeping.
struct SlotLayout {
    var portrait: [NSLayoutConstraint] = []
    var landscape: [NSLayoutConstraint] = []
    var height: NSLayoutConstraint?
    var isLandscape = false
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
