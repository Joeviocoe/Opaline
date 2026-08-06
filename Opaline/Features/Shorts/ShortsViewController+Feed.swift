import UIKit

// MARK: - Sequence loading & metadata

extension ShortsViewController {
    func loadNextPage() {
        guard !isLoading, let seed else {
            return
        }
        isLoading = true
        shortsService.fetchShortsSequence(seed: seed) { [weak self] result in
            DispatchQueue.main.async {
                self?.handlePage(result)
            }
        }
    }

    private func handlePage(_ result: Result<ShortsSequencePage, Error>) {
        isLoading = false
        guard case .success(let page) = result else {
            AppLog.innertube("shorts sequence failed")
            seed = nil
            return
        }
        seed = page.continuation
        let known = Set(videos.map { $0.id })
        let fresh = page.videos.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else {
            return
        }
        let range = videos.count ..< (videos.count + fresh.count)
        videos.append(contentsOf: fresh)
        guard playerView.superview != nil else {
            // Nothing is playing yet and the collection may not have laid
            // out — inserting into a view that never counted its items is an
            // inconsistency, and there is no live player to protect.
            collectionView.reloadData()
            return
        }
        // Append rather than reload: a reload rebuilds the current cell and
        // tears the live player out of the view hierarchy mid-playback.
        collectionView.insertItems(
            at: range.map { IndexPath(item: $0, section: 0) }
        )
    }

    /// The sequence endpoint returns no titles — fill them in from the watch
    /// page once a short is on screen.
    func fetchMetadata(for index: Int) {
        let video = videos[index]
        // Fetched for every short, not just the untitled ones from the
        // sequence — the like count, comment count and channel avatar only
        // exist on the watch page.
        guard metadataFetched.insert(video.id).inserted else {
            return
        }
        watchService.fetchWatchPage(
            video: video, cancellationToken: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let page) = result else {
                    return
                }
                self?.applyMetadata(page, at: index)
            }
        }
    }

    func applyMetadata(_ page: WatchPage, at index: Int) {
        let video = page.video
        guard index < videos.count, videos[index].id == video.id else {
            return
        }
        pages[video.id] = page
        videos[index] = Video(
            id: video.id,
            title: video.title,
            channelId: video.channelId,
            channelName: video.channelName,
            channelAvatarURL: video.channelAvatarURL,
            thumbnailURL: videos[index].thumbnailURL,
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            duration: video.duration,
            isShort: true
        )
        let indexPath = IndexPath(item: index, section: 0)
        (collectionView.cellForItem(at: indexPath) as? ShortsCell)?
            .configure(with: videos[index])
        refreshOverlay(for: video.id)
    }

    func likeStatus(for videoId: String) -> LikeStatus? {
        likeOverrides[videoId] ?? pages[videoId]?.likeStatus
    }

    func setLikeStatus(_ status: LikeStatus, for videoId: String) {
        likeOverrides[videoId] = status
    }

    func watchPage(for videoId: String) -> WatchPage? {
        pages[videoId]
    }

    /// Pushes engagement state into the on-screen cell for `videoId`, if it
    /// is the one showing — off-screen cells pick it up when configured.
    func refreshOverlay(for videoId: String) {
        guard let index = videos.firstIndex(where: { $0.id == videoId })
        else {
            return
        }
        let page = pages[videoId]
        let indexPath = IndexPath(item: index, section: 0)
        (collectionView.cellForItem(at: indexPath) as? ShortsCell)?
            .configure(
                likeCount: page?.likeCount,
                commentCount: page?.commentCount,
                likeStatus: likeStatus(for: videoId),
                avatarURL: page?.channelInfo?.avatarURL
                    ?? videos[index].channelAvatarURL
            )
    }
}
