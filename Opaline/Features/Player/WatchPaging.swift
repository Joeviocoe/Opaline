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

/// Paging size for the lazily-revealed related list. Comments page
/// themselves — the server decides the batch and the table pulls the next
/// one as the tail comes into view.
enum WatchPaging {
    static let relatedBatch = 5
}

/// Memoizes the last `applyDescriptionText()` output so repeat calls with
/// the same text and theme reuse it instead of re-running `LinkifiedText`.
struct DescriptionAttributedCache {
    let text: String
    let isDark: Bool
    let attributed: NSAttributedString
}
