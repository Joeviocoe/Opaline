import Foundation

// MARK: - Saving the comments a video had

extension VideoDownloader {
    /// Enough to scroll for a while without the list ending abruptly. It is
    /// text: five pages of a busy video measure in tens of kilobytes, so the
    /// limit is about how long the fetch takes, not about disk.
    static let commentPagesToSave = 5

    func fetchComments(for videoId: String) {
        collectComments(videoId: videoId, continuation: nil, collected: [])
    }

    /// One page after another, following the server's own tokens — the same
    /// walk the screen does when someone keeps scrolling.
    private func collectComments(
        videoId: String,
        continuation: String?,
        collected: [DownloadStore.StoredComments]
    ) {
        apiClient.fetchComments(
            videoId: videoId,
            continuation: continuation,
            cancellationToken: nil
        ) { [weak self] result in
            guard case .success(let page) = result else {
                self?.finishComments(collected, videoId: videoId)
                return
            }
            let pages = collected + [
                DownloadStore.StoredComments(
                    requestedWith: continuation, page: page
                )
            ]
            guard let next = page.continuation,
                  pages.count < Self.commentPagesToSave else {
                self?.finishComments(pages, videoId: videoId)
                return
            }
            self?.collectComments(
                videoId: videoId, continuation: next, collected: pages
            )
        }
    }

    private func finishComments(
        _ pages: [DownloadStore.StoredComments],
        videoId: String
    ) {
        guard !pages.isEmpty else {
            return
        }
        DownloadStore.saveComments(pages, for: videoId)
    }
}
