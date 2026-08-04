import UIKit

// MARK: - Comments (network + preview)

extension WatchViewController {
    /// The official app skips the pinned comment in the preview — it isn't
    /// necessarily the conversation's top comment. `Comment` only parses
    /// `isPinned` (see `InnertubeClient+CommentBuilding.assembleComment`),
    /// not channel-owner authorship, so that half of the reference rule
    /// can't be implemented without touching `Core/API`. Falls back to the
    /// first comment if everything happens to be pinned.
    private var previewComment: Comment? {
        comments.first { !$0.isPinned } ?? comments.first
    }

    func resetComments() {
        comments = []
        commentsContinuation = nil
        visibleCommentsCount = WatchPaging.commentsPage
        isLoadingComments = false
        hasLoadedComments = false
        collapseComments()
        setCommentsTitle("player.comments.title".localized)
        renderComments()
    }

    func loadComments(continuation: String? = nil) {
        guard !isLoadingComments else {
            return
        }
        isLoadingComments = true
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
        hasLoadedComments = true
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
            // Only the first page carries the server's total ("546
            // Comments"); continuations come back without one. Falling back
            // to the loaded count there rewrote the header down to 29.
            if let title = page.title {
                setCommentsTitle(title)
            } else if continuation == nil {
                setCommentsTitle(
                    "player.comments.titleCount".localized(with: comments.count)
                )
            }
        }
        renderComments()
    }

    /// The in-flow section header and the panel's own header show the same
    /// text — kept in sync here rather than duplicating state.
    private func setCommentsTitle(_ text: String) {
        commentsLabel.text = text
        commentsPanel.titleLabel.text = text
    }

    func appendNewComments(_ newComments: [Comment]) {
        let existingIds = Set(comments.map(\.id))
        let unique = newComments.filter {
            !existingIds.contains($0.id)
        }
        comments.append(contentsOf: unique)
    }

    /// Refreshes both surfaces that can show comments: the always-present
    /// one-row preview, and the expanded table (cheap to reload even while
    /// hidden — only visible rows are ever instantiated).
    func renderComments() {
        updateCommentsPreview()
        commentsTableView.reloadData()
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

    /// Shows exactly one row: a skeleton while the first page is in flight,
    /// an empty message once it's known there is nothing, or one real
    /// comment — reusing the single shared `commentPreviewContentView`
    /// rather than building a new view.
    ///
    /// Stays visible while the panel is open: everything under the player
    /// keeps its place and the panel simply slides over it.
    func updateCommentsPreview() {
        commentsStackView.arrangedSubviews.forEach {
            commentsStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if comments.isEmpty {
            if hasLoadedComments, !isLoadingComments {
                renderPreviewEmptyMessage()
            } else {
                renderPreviewSkeleton()
            }
            return
        }
        guard let preview = previewComment else {
            return
        }
        commentPreviewContentView.configure(preview, linkDelegate: self)
        commentsStackView.addArrangedSubview(commentPreviewContentView)
    }

    private func renderPreviewSkeleton() {
        let row = UIView()
        row.layer.cornerRadius = 8
        row.layer.masksToBounds = true
        row.heightAnchor.constraint(
            equalToConstant: 56
        ).isActive = true
        commentsStackView.addArrangedSubview(row)
        // The shimmer overlay is frame-based, so the row needs its size
        // before it is added.
        commentsStackView.layoutIfNeeded()
        row.showSkeleton()
    }

    private func renderPreviewEmptyMessage() {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = ThemeManager.shared.secondaryText
        label.text = "player.comments.unavailableYet".localized
        commentsStackView.addArrangedSubview(label)
    }
}
