import UIKit

// MARK: - Sequence loading & metadata

extension ShortsViewController {
    func loadNextPage() {
        guard !isLoading else {
            return
        }
        // The shelf the pool came from comes first: its shorts are still the
        // ones from this surface, while the sequence is the server's own pick.
        if let shelf = shelfToken {
            isLoading = true
            feedService.fetchNextPage(continuation: shelf) { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleShelfPage(result)
                }
            }
            return
        }
        guard let seed else {
            return
        }
        isLoading = true
        shortsService.fetchShortsSequence(seed: seed) { [weak self] result in
            DispatchQueue.main.async {
                self?.handlePage(result)
            }
        }
    }

    /// A drained shelf page. Its shorts are shuffled in like the rest of the
    /// pool; when the shelf runs dry the sequence takes over.
    private func handleShelfPage(_ result: Result<FeedPage, Error>) {
        isLoading = false
        guard case .success(let page) = result else {
            AppLog.innertube("shorts shelf drain failed")
            shelfToken = nil
            return
        }
        shelfToken = page.continuation
        append(page.videos.filter { $0.isShort }.shuffled())
    }

    private func handlePage(_ result: Result<ShortsSequencePage, Error>) {
        isLoading = false
        guard case .success(let page) = result else {
            AppLog.innertube("shorts sequence failed")
            seed = nil
            return
        }
        seed = page.continuation
        append(page.videos)
    }

    private func append(_ incoming: [Video]) {
        let known = Set(videos.map { $0.id })
        let fresh = incoming.filter { !known.contains($0.id) }
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
        guard index == attachedIndex else {
            return
        }
        let page = pages[videoId]
        overlay.configure(with: videos[index])
        overlay.configure(
            likeCount: page?.likeCount,
            commentCount: page?.commentCount,
            likeStatus: likeStatus(for: videoId),
            avatarURL: page?.channelInfo?.avatarURL
                ?? videos[index].channelAvatarURL
        )
    }
}
