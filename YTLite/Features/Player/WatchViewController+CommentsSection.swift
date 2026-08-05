import UIKit

// MARK: - Expand / Collapse

extension WatchViewController {
    @objc
    func expandComments() {
        guard !isCommentsExpanded else {
            return
        }
        setCommentsExpanded(true)
    }

    @objc
    func collapseComments() {
        guard isCommentsExpanded else {
            return
        }
        setCommentsExpanded(false)
    }

    /// Portrait: the panel is a floating overlay above the untouched related
    /// list (see `WatchViewController+CommentsPanel`). Landscape: it still
    /// swaps into the related list's sidebar slot, one visible at a time.
    private func setCommentsExpanded(_ expanded: Bool) {
        isCommentsExpanded = expanded
        commentsTableView.reloadData()
        view.setNeedsLayout()
        // Layout first, animate second. The other order let
        // `layoutCommentsPanel` assign the panel's final offset outside the
        // animation block, so opening snapped into place while closing —
        // which returns early once `isCommentsExpanded` is false — animated.
        updateLayoutForSize()
        if expanded {
            presentCommentsPanel()
        } else {
            dismissCommentsPanel()
        }
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate

extension WatchViewController: UITableViewDataSource {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    )
        -> Int {
        commentRows.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    )
        -> UITableViewCell {
        commentsCell(at: indexPath)
    }
}

extension WatchViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch commentRows[safe: indexPath.row] {
        case .replyToggle(let index):
            toggleReplies(at: index)
        case .moreReplies(let index):
            loadReplies(at: index)
        default:
            break
        }
    }

    /// Endless scrolling, as in the official app: the next page is fetched
    /// while the tail is still a few rows away instead of behind a button.
    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard indexPath.row >= commentRows.count - 4,
              let continuation = commentsContinuation,
              !isLoadingComments
        else {
            return
        }
        loadComments(continuation: continuation)
    }

    /// Self-sizing rows re-measure every time they scroll back in, which on
    /// a long list makes the scroll indicator jump. Remembering what a row
    /// actually measured keeps the estimate honest.
    func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard let key = commentRows[safe: indexPath.row]?.heightKey else {
            return
        }
        commentHeightCache[key] = cell.frame.height
    }

    func tableView(
        _ tableView: UITableView,
        estimatedHeightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        commentRows[safe: indexPath.row]?.heightKey
            .flatMap { commentHeightCache[$0] } ?? 80
    }
}

// MARK: - Cells

private extension WatchViewController {
    func commentsCell(at indexPath: IndexPath) -> UITableViewCell {
        switch commentRows[safe: indexPath.row] {
        case .comment(let comment):
            return commentCell(comment, isReply: false, at: indexPath)
        case .reply(let comment):
            return commentCell(comment, isReply: true, at: indexPath)
        case .replyToggle(let index):
            return replyToggleCell(at: index, isMore: false)
        case .moreReplies(let index):
            return replyToggleCell(at: index, isMore: true)
        case .status(let text):
            return statusCell(text: text, isSkeleton: text == nil, isAction: false)
        case nil:
            return UITableViewCell()
        }
    }

    func commentCell(
        _ comment: Comment,
        isReply: Bool,
        at indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = commentsTableView.dequeueReusableCell(
            withIdentifier: CommentCell.reuseId,
            for: indexPath
        ) as? CommentCell
            ?? CommentCell(style: .default, reuseIdentifier: CommentCell.reuseId)
        cell.configure(comment, linkDelegate: self, isReply: isReply)
        return cell
    }

    /// Both reply rows are the same text button: the one above the replies
    /// toggles them, the trailing one pulls the next page.
    func replyToggleCell(at index: Int, isMore: Bool) -> UITableViewCell {
        let thread = commentThreads[safe: index]
        let isLoading = thread?.isLoadingReplies == true && isMore
        let text: String
        if isLoading {
            text = "player.comments.loading".localized
        } else {
            text = isMore
                ? "player.comments.moreReplies".localized
                : (thread?.toggleText ?? "")
        }
        return statusCell(
            text: text,
            isSkeleton: false,
            isAction: !isLoading,
            isReply: true
        )
    }

    func statusCell(
        text: String?,
        isSkeleton: Bool,
        isAction: Bool,
        isReply: Bool = false
    ) -> UITableViewCell {
        let cell = commentsTableView.dequeueReusableCell(
            withIdentifier: CommentStatusCell.reuseId
        ) as? CommentStatusCell
            ?? CommentStatusCell(
                style: .default,
                reuseIdentifier: CommentStatusCell.reuseId
            )
        cell.configure(
            text: text,
            isSkeleton: isSkeleton,
            isAction: isAction,
            isReply: isReply
        )
        // Status rows are not comments — a rule under them reads as a
        // divider before content that isn't there. Pushing the inset past
        // the row's width is the standard way to drop just this one.
        cell.separatorInset = UIEdgeInsets(
            top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0
        )
        return cell
    }
}

private extension CommentRow {
    /// Stable identity for the measured-height cache; the paging and toggle
    /// rows change text as they go, so they keep the default estimate.
    var heightKey: String? {
        switch self {
        case .comment(let comment):
            return comment.id
        case .reply(let comment):
            return "r\(comment.id)"
        default:
            return nil
        }
    }
}
