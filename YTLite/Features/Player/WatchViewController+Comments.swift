import UIKit

// MARK: - Comments
extension WatchViewController {
    func resetComments() {
        comments = []
        commentsContinuation = nil
        visibleCommentsCount = WatchPaging.commentsPage
        isLoadingComments = false
        commentsLabel.text = "player.comments.title".localized
        // Skeleton, not "no comments yet": nothing has been asked for yet, and
        // announcing an empty section before the request even goes out reads
        // as a verdict.
        clearComments()
        renderCommentSkeletons()
        updateLoadMoreButton()
    }

    private func clearComments() {
        commentsStackView.arrangedSubviews.forEach { vw in
            commentsStackView.removeArrangedSubview(vw)
            vw.removeFromSuperview()
        }
    }

    func loadComments(continuation: String? = nil) {
        guard !isLoadingComments else {
            return
        }
        isLoadingComments = true
        loadMoreCommentsButton.isEnabled = false
        loadMoreCommentsButton.isHidden = comments.isEmpty
        loadMoreCommentsButton.setTitle(
            "player.comments.loading".localized,
            for: .normal
        )
        if comments.isEmpty {
            commentsLabel.text = "player.comments.loading".localized
            renderComments()
        }
        client.fetchComments(
            videoId: initialVideo.id,
            continuation: continuation,
            cancellationToken: pageLoadToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleCommentsResult(
                    result,
                    continuation: continuation
                )
            }
        }
    }

    func handleCommentsResult(
        _ result: Result<CommentsPage, Error>,
        continuation: String?
    ) {
        isLoadingComments = false
        switch result {
        case .failure(let error):
            AppLog.player(
                "comments load failed "
                + "\(initialVideo.id): \(error)"
            )
            if comments.isEmpty {
                commentsLabel.text =
                    "player.comments.unavailable".localized
            }
        case .success(let page):
            commentsContinuation = page.continuation
            if continuation == nil {
                // A first page replaces the list wholesale, so the rows on
                // screen are no longer a prefix of it — `renderComments`
                // appends, and would otherwise leave stale rows behind.
                comments = page.comments
                clearComments()
            } else {
                appendNewComments(page.comments)
            }
            commentsLabel.text = page.title
                ?? "player.comments.titleCount"
                    .localized(with: comments.count)
        }
        renderComments()
    }

    func appendNewComments(_ newComments: [Comment]) {
        let existingIds = Set(comments.map(\.id))
        let unique = newComments.filter {
            !existingIds.contains($0.id)
        }
        comments.append(contentsOf: unique)
    }

    /// Appends only the rows not yet on screen instead of tearing the whole
    /// stack down every call — `expandCommentsIfNeeded`/pagination call this
    /// repeatedly and the comment order never changes. Falls back to a full
    /// rebuild whenever the stack isn't already showing a clean prefix of
    /// `comments` (skeleton/empty state, or a genuine reset via
    /// `clearComments()`).
    func renderComments() {
        guard !comments.isEmpty else {
            clearComments()
            renderEmptyComments()
            updateLoadMoreButton()
            view.setNeedsLayout()
            return
        }
        let target = Array(comments.prefix(visibleCommentsCount))
        let rendered = commentsStackView.arrangedSubviews
        var renderedCount = rendered.allSatisfy { $0 is CommentRowView }
            ? rendered.count
            : 0
        // Anything other than "the stack already shows a clean prefix of
        // `target`" (skeleton/empty rows, or a shrunk `target`) needs a
        // full rebuild rather than an append.
        let needsRebuild = (renderedCount == 0 && !rendered.isEmpty)
            || renderedCount > target.count
        if needsRebuild {
            clearComments()
            renderedCount = 0
        }
        for comment in target[renderedCount...] {
            commentsStackView.addArrangedSubview(makeCommentView(comment))
        }
        updateLoadMoreButton()
        view.setNeedsLayout()
    }

    func renderEmptyComments() {
        guard !isLoadingComments else {
            renderCommentSkeletons()
            return
        }
        let emptyLabel = UILabel()
        emptyLabel.numberOfLines = 0
        emptyLabel.font = UIFont.systemFont(ofSize: 13)
        emptyLabel.textColor =
            ThemeManager.shared.secondaryText
        emptyLabel.text = "player.comments.unavailableYet".localized
        commentsStackView.addArrangedSubview(emptyLabel)
    }

    /// Three shimmering rows the height of a short comment — the same trick
    /// the feeds use, instead of a "Loading…" line that reflows the layout
    /// once the real comments land.
    private func renderCommentSkeletons() {
        let rows = (0 ..< 3).map { _ -> UIView in
            let row = UIView()
            row.layer.cornerRadius = 8
            row.layer.masksToBounds = true
            row.heightAnchor.constraint(
                equalToConstant: 56
            ).isActive = true
            commentsStackView.addArrangedSubview(row)
            return row
        }
        // The shimmer overlay is frame-based, so the rows need their size
        // before it is added.
        commentsStackView.layoutIfNeeded()
        rows.forEach { $0.showSkeleton() }
    }

    func updateLoadMoreButton() {
        let hasMore = visibleCommentsCount < comments.count
        let hasCont = commentsContinuation != nil
        loadMoreCommentsButton.isHidden =
            !hasMore && !hasCont
        if isLoadingComments {
            loadMoreCommentsButton.setTitle(
                "player.comments.loading".localized,
                for: .normal
            )
            loadMoreCommentsButton.isEnabled = false
        } else {
            loadMoreCommentsButton.setTitle(
                "player.comments.loadMore".localized,
                for: .normal
            )
            loadMoreCommentsButton.isEnabled = true
        }
    }

    func makeCommentView(
        _ comment: Comment
    ) -> UIView {
        CommentViewBuilder.makeCommentView(comment, linkDelegate: self)
    }

    func expandRelatedIfNeeded() {
        guard visibleRelatedVideos.count
                < allRelatedVideos.count else {
            return
        }
        let nextCount = min(
            visibleRelatedVideos.count + WatchPaging.relatedBatch,
            allRelatedVideos.count
        )
        visibleRelatedVideos = Array(
            allRelatedVideos.prefix(nextCount)
        )
        relatedCollectionView.reloadData()
        view.setNeedsLayout()
    }

    func expandCommentsIfNeeded() {
        if visibleCommentsCount < comments.count {
            visibleCommentsCount += WatchPaging.commentsPage
            renderComments()
        } else if commentsContinuation != nil,
                  !isLoadingComments {
            loadComments(continuation: commentsContinuation)
        }
    }
}
