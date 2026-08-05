import Foundation

/// One top-level comment plus whatever replies have been pulled in for it.
/// YouTube nests replies exactly one level deep — a reply to a reply comes
/// back in the same flat list — so a two-level model is the whole tree.
struct CommentThread {
    let comment: Comment
    var replies: [Comment] = []
    /// Next replies page; starts as the thread's first-page token and is
    /// `nil` once every reply has been loaded.
    var repliesContinuation: String?
    var isExpanded = false
    var isLoadingReplies = false

    var hasReplies: Bool {
        comment.replyContinuation != nil
    }

    /// Label of the row that expands or collapses this thread.
    var toggleText: String {
        if isExpanded {
            return "player.comments.hideReplies".localized
        }
        guard let count = comment.replyCount, !count.isEmpty else {
            return "player.comments.viewReplies".localized
        }
        return "player.comments.replies".localized(with: count)
    }

    init(comment: Comment) {
        self.comment = comment
        repliesContinuation = comment.replyContinuation
    }
}

/// A flattened table row. The tree is rebuilt into this array whenever a
/// thread expands or a page lands, so the data source stays O(1) per row —
/// nothing walks the thread list while scrolling.
enum CommentRow {
    case comment(Comment)
    case reply(Comment)
    /// Expands or collapses thread N.
    case replyToggle(Int)
    /// Loads thread N's next page of replies.
    case moreReplies(Int)
    /// Skeleton when `nil`, otherwise a message (empty / loading / failed).
    case status(String?)
}

extension Array where Element == CommentThread {
    /// Flattens threads into rows, expanded threads contributing their
    /// loaded replies indented underneath.
    func commentRows() -> [CommentRow] {
        var rows: [CommentRow] = []
        rows.reserveCapacity(count * 2)
        for (index, thread) in enumerated() {
            rows.append(.comment(thread.comment))
            guard thread.hasReplies else {
                continue
            }
            rows.append(.replyToggle(index))
            guard thread.isExpanded else {
                continue
            }
            rows.append(contentsOf: thread.replies.map { CommentRow.reply($0) })
            // Before the first page lands there is nothing to page past yet,
            // and a second pill saying "loading" flashed under the toggle.
            if thread.repliesContinuation != nil, !thread.replies.isEmpty {
                rows.append(.moreReplies(index))
            }
        }
        return rows
    }
}
