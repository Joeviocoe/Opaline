import Foundation

// MARK: - Saving the comments a video had

extension VideoDownloader {
    /// Enough to scroll for a while without the list ending abruptly. It is
    /// text: five pages of a busy video measure in tens of kilobytes, so the
    /// limit is about how long the fetch takes, not about disk.
    static let commentPagesToSave = 5

    func fetchComments(for videoId: String) {
        switch DownloadPreferences.comments {
        case .none:
            return
        case .top:
            collectComments(videoId: videoId, continuation: nil, collected: [])
        case .newest:
            collectNewest(videoId: videoId)
        }
    }

    /// The sort menu comes from the server already localized, so the wanted
    /// order cannot be matched by name — it is the second entry, the way the
    /// screen itself lists them. Its first page is stored under a nil token
    /// so that offline it answers as page one.
    private func collectNewest(videoId: String) {
        apiClient.fetchComments(
            videoId: videoId, continuation: nil, cancellationToken: nil
        ) { [weak self] result in
            guard case .success(let page) = result,
                  let newest = page.sortOptions[safe: 1] else {
                self?.collectComments(
                    videoId: videoId, continuation: nil, collected: []
                )
                return
            }
            self?.collectComments(
                videoId: videoId,
                continuation: newest.token,
                collected: [],
                storeFirstAsPageOne: true
            )
        }
    }

    /// One page after another, following the server's own tokens — the same
    /// walk the screen does when someone keeps scrolling.
    private func collectComments(
        videoId: String,
        continuation: String?,
        collected: [DownloadStore.StoredComments],
        storeFirstAsPageOne: Bool = false
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
            let key = storeFirstAsPageOne && collected.isEmpty
                ? nil
                : continuation
            let pages = collected + [
                DownloadStore.StoredComments(requestedWith: key, page: page)
            ]
            guard let next = page.continuation,
                  pages.count < Self.commentPagesToSave else {
                self?.finishComments(pages, videoId: videoId)
                return
            }
            self?.collectComments(
                videoId: videoId,
                continuation: next,
                collected: pages,
                storeFirstAsPageOne: storeFirstAsPageOne
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
