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
        commentsRowCount()
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
        guard isCommentsLoadMoreRow(indexPath) else {
            return
        }
        expandCommentsIfNeeded()
    }
}

// MARK: - Table row model

private extension WatchViewController {
    /// One row while empty (skeleton or message), otherwise the visible
    /// comments plus one trailing "load more" row when there is more to
    /// fetch — everything past that stays unbuilt until it scrolls in.
    func commentsRowCount() -> Int {
        guard !comments.isEmpty else {
            return 1
        }
        let visible = min(visibleCommentsCount, comments.count)
        let hasMore = visible < comments.count || commentsContinuation != nil
        return visible + (hasMore ? 1 : 0)
    }

    func isCommentsLoadMoreRow(_ indexPath: IndexPath) -> Bool {
        guard !comments.isEmpty else {
            return false
        }
        return indexPath.row >= min(visibleCommentsCount, comments.count)
    }

    func commentsCell(at indexPath: IndexPath) -> UITableViewCell {
        guard !comments.isEmpty else {
            return statusCell(
                text: isLoadingComments ? nil : "player.comments.unavailableYet".localized,
                isSkeleton: isLoadingComments,
                isAction: false
            )
        }
        let visible = min(visibleCommentsCount, comments.count)
        guard indexPath.row < visible else {
            return statusCell(
                text: isLoadingComments
                    ? "player.comments.loading".localized
                    : "player.comments.loadMore".localized,
                isSkeleton: false,
                isAction: true
            )
        }
        let cell = commentsTableView.dequeueReusableCell(
            withIdentifier: CommentCell.reuseId,
            for: indexPath
        ) as? CommentCell ?? CommentCell(style: .default, reuseIdentifier: CommentCell.reuseId)
        cell.configure(comments[indexPath.row], linkDelegate: self)
        return cell
    }

    func statusCell(text: String?, isSkeleton: Bool, isAction: Bool) -> UITableViewCell {
        let cell = commentsTableView.dequeueReusableCell(
            withIdentifier: CommentStatusCell.reuseId
        ) as? CommentStatusCell
            ?? CommentStatusCell(style: .default, reuseIdentifier: CommentStatusCell.reuseId)
        cell.configure(text: text, isSkeleton: isSkeleton, isAction: isAction)
        // Status rows are not comments — a rule under "load more" reads as a
        // divider before content that isn't there. Pushing the inset past
        // the row's width is the standard way to drop just this one.
        cell.separatorInset = UIEdgeInsets(
            top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0
        )
        return cell
    }
}
