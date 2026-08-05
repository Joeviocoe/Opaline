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
        let first = commentThreads.first { !$0.comment.isPinned }
            ?? commentThreads.first
        return first?.comment
    }

    func resetComments() {
        commentThreads = []
        commentsContinuation = nil
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
        if commentThreads.isEmpty {
            commentsLabel.text = "player.comments.loading".localized
        }
        renderComments()
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
            // Dropping the token stops an endless retry loop at the tail of
            // a list whose next page keeps failing.
            commentsContinuation = nil
            if commentThreads.isEmpty {
                commentsLabel.text =
                    "player.comments.unavailable".localized
            }
        case .success(let page):
            commentsContinuation = page.continuation
            if continuation == nil {
                commentThreads = page.comments.map(CommentThread.init)
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
                    "player.comments.titleCount"
                        .localized(with: commentThreads.count)
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
        let existingIds = Set(commentThreads.map(\.comment.id))
        commentThreads.append(contentsOf: newComments
            .filter { !existingIds.contains($0.id) }
            .map(CommentThread.init))
    }

    // MARK: - Replies

    /// Expands or collapses a thread; the first expansion pulls its replies.
    func toggleReplies(at index: Int) {
        guard commentThreads.indices.contains(index) else {
            return
        }
        commentThreads[index].isExpanded.toggle()
        if commentThreads[index].isExpanded,
           commentThreads[index].replies.isEmpty {
            loadReplies(at: index)
        } else {
            renderComments()
        }
    }

    func loadReplies(at index: Int) {
        guard commentThreads.indices.contains(index),
              !commentThreads[index].isLoadingReplies,
              let token = commentThreads[index].repliesContinuation
        else {
            return
        }
        commentThreads[index].isLoadingReplies = true
        renderComments()
        client.fetchComments(
            videoId: initialVideo.id,
            continuation: token,
            cancellationToken: pageLoadToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleRepliesResult(result, at: index)
            }
        }
    }

    private func handleRepliesResult(
        _ result: Result<CommentsPage, Error>,
        at index: Int
    ) {
        guard commentThreads.indices.contains(index) else {
            return
        }
        commentThreads[index].isLoadingReplies = false
        switch result {
        case .failure(let error):
            AppLog.player("replies load failed: \(error)")
            commentThreads[index].repliesContinuation = nil
        case .success(let page):
            let existing = Set(commentThreads[index].replies.map(\.id))
            commentThreads[index].replies.append(
                contentsOf: page.comments.filter {
                    !existing.contains($0.id)
                }
            )
            commentThreads[index].repliesContinuation = page.continuation
        }
        renderComments()
    }

    // MARK: - Rendering

    /// Refreshes both surfaces that can show comments: the always-present
    /// one-row preview, and the expanded table (cheap to reload even while
    /// hidden — only visible rows are ever instantiated).
    func renderComments() {
        commentRows = buildCommentRows()
        updateCommentsPreview()
        commentsTableView.reloadData()
        view.setNeedsLayout()
    }

    private func buildCommentRows() -> [CommentRow] {
        guard !commentThreads.isEmpty else {
            let isDone = hasLoadedComments && !isLoadingComments
            let empty = "player.comments.unavailableYet".localized
            return [.status(isDone ? empty : nil)]
        }
        var rows = commentThreads.commentRows()
        if isLoadingComments || commentsContinuation != nil {
            rows.append(.status("player.comments.loading".localized))
        }
        return rows
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
        guard let preview = previewComment else {
            if hasLoadedComments, !isLoadingComments {
                renderPreviewEmptyMessage()
            } else {
                renderPreviewSkeleton()
            }
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
