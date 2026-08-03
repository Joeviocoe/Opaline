import UIKit

// MARK: - Comments
extension WatchViewController {
    func resetComments() {
        comments = []
        commentsContinuation = nil
        visibleCommentsCount = commentsPageSize
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
                comments = page.comments
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

    func renderComments() {
        clearComments()
        if comments.isEmpty {
            renderEmptyComments()
        } else {
            for comment in comments.prefix(
                visibleCommentsCount
            ) {
                commentsStackView.addArrangedSubview(
                    makeCommentView(comment)
                )
            }
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
            visibleRelatedVideos.count + relatedBatchSize,
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
            visibleCommentsCount += commentsPageSize
            renderComments()
        } else if commentsContinuation != nil,
                  !isLoadingComments {
            loadComments(continuation: commentsContinuation)
        }
    }
}
