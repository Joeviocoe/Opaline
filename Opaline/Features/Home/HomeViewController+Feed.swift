import UIKit

// MARK: - Feed loading

extension HomeViewController {
    func setupToolbar() {
        ToolbarManager.shared.install(in: self)
    }

    /// Adopts a feed that background refresh wrote while the app was away.
    /// Two guards keep this from becoming the shelf-reshuffle the whole
    /// revalidation change was made to stop: the list must be at the top
    /// (nothing moves under a scrolling finger) and the cache must actually
    /// be newer than what is on screen (background refresh runs about
    /// hourly, so a quick app switch changes nothing).
    func adoptFreshCacheIfNeeded() {
        guard let collectionView, collectionView.contentOffset.y <= 1,
              let cachedAt = cache.feedUpdatedAt("home"),
              cachedAt > appliedFeedAt,
              let cachedPage = cache.cachedHomeFeed()
        else {
            return
        }
        AppLog.home("adopting feed refreshed in the background")
        resetShelfDrain()
        applyCachedPage(cachedPage)
        rebuildChips()
    }

    func loadCachedOrFetchFeed() {
        cache.loadHomeFeed { [weak self] cachedPage in
            guard let self else {
                return
            }
            if let cachedPage {
                AppLog.home("cache-hit → showing \(cachedPage.videos.count) videos instantly")
                self.isLoadingInitial = false
                self.spinner.stopAnimating()
                self.resetShelfDrain()
                self.applyCachedPage(cachedPage)
                // Revalidating replaces the whole feed — YouTube reorders
                // shelves on every request, so the screen visibly rebuilds
                // and thumbnails reload. Skip it while the cache is recent;
                // background refresh keeps it that way, pull-to-refresh
                // forces it, and a stale continuation triggers it lazily.
                let age = self.cache.feedAge("home") ?? .greatestFiniteMagnitude
                guard age >= AppCache.feedRevalidateAfter else {
                    AppLog.home("cache is \(Int(age / 60))m old → no revalidation")
                    // The cache holds one page, so it only knows a few
                    // shelves. Collect the rest the way a fresh load does —
                    // this appends pages below the fold and never touches
                    // what is already on screen.
                    self.beginChipDiscovery()
                    self.continueChipPrefetchIfNeeded()
                    // Nothing else is going to hit the network for this
                    // screen, so the other tabs may as well start now.
                    self.postFeedDidSettle()
                    return
                }
                AppLog.home("revalidating feed in background")
                self.loadFeed()
            } else {
                AppLog.home("no cache → loading from network")
                self.loadFeed()
            }
        }
    }

    /// Shows a cached page and remembers how fresh it was, so a later
    /// background refresh can be recognised as newer than the screen.
    private func applyCachedPage(_ page: FeedPage) {
        appliedFeedAt = cache.feedUpdatedAt("home") ?? Date()
        setPage(enqueueShelves(from: page))
    }

    /// Skipping revalidation on launch means the cached tokens can be hours
    /// old; the first dead one is the signal to refetch, so scrolling never
    /// dead-ends. Once per session — a genuinely offline device shouldn't
    /// retry on every attempt.
    func revalidateOnceAfterStaleToken() {
        guard !didRevalidateAfterStaleToken else {
            return
        }
        didRevalidateAfterStaleToken = true
        AppLog.home("stale continuation → revalidating")
        loadFeed()
    }

    private func showFeedError() {
        if OAuthClient.shared.isAnonymous {
            signInEmptyView.isHidden = false
        } else {
            errorLabel.isHidden = false
        }
    }

    func loadFeed() {
        let t0 = Date()
        AppLog.home("network fetch start")
        errorLabel.isHidden = true
        signInEmptyView.isHidden = true
        resetShelfDrain()
        beginChipDiscovery()
        let generation = feedGeneration
        service.fetchHomeFeed { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.feedGeneration == generation else {
                    return
                }
                let ms = Int(Date().timeIntervalSince(t0) * 1_000)
                self.spinner.stopAnimating()
                self.handleFeedResult(result, ms: ms)
            }
        }
    }

    /// The refresh control and the "feed settled" signal wait for the
    /// expanded page — the first shelf costs a few more requests.
    private func handleFeedResult(
        _ result: Result<FeedPage, Error>,
        ms: Int
    ) {
        switch result {
        case .success(let page):
            AppLog.home("network fetch done \(ms)ms videos=\(page.videos.count)")
            expandRecommended(page) { [weak self] expanded in
                guard let self else {
                    return
                }
                self.endRefreshing()
                self.postFeedDidSettle()
                self.applyFreshFeed(expanded)
            }
        case .failure(let err):
            AppLog.home("network fetch failed \(ms)ms: \(err)")
            endRefreshing()
            postFeedDidSettle()
            endChipDiscovery()
            // Keep cached/stale content when revalidation
            // fails offline — only blank screens get the error.
            if videoCount == 0 {
                setPage(FeedPage(videos: [], continuation: nil))
                showFeedError()
            }
        }
    }

    private func postFeedDidSettle() {
        NotificationCenter.default.post(
            name: .homeFeedDidSettle, object: nil
        )
    }

    /// Replaces the session with a freshly fetched feed: cached and
    /// previously accumulated pages carry expiring continuation
    /// tokens, so runs and chips restart from this page.
    private func applyFreshFeed(_ page: FeedPage) {
        cache.setHomeFeed(page)
        appliedFeedAt = Date()
        startFreshSession()
        setPage(enqueueShelves(from: page))
        rebuildChips()
        applyPendingChipReselect()
        continueChipPrefetchIfNeeded()
    }
}

extension Notification.Name {
    /// The home feed's network fetch finished, one way or the other.
    /// The launch path uses it to start warming the other tabs only
    /// once the visible screen has stopped competing for the link.
    static let homeFeedDidSettle = Notification.Name(
        "homeFeedDidSettle"
    )
}

// MARK: - Recommended shelf expansion

extension HomeViewController {
    /// Pages fetched from the first shelf before the feed is shown.
    /// Ten videos each.
    private static let recommendedExtraPages = 3

    /// Swaps the first shelf's videos and advances its token, so the
    /// later shelf drain carries on past what was just consumed
    /// instead of replaying it.
    private static func replacingFirstShelf(
        in page: FeedPage,
        with videos: [Video],
        oldToken: String,
        newToken: String?
    ) -> FeedPage {
        var page = page
        page.videos = videos + page.videos.dropFirst(
            page.shelves?.first?.count ?? 0
        )
        var shelves = page.shelves ?? []
        shelves[0] = FeedShelf(
            title: shelves[0].title,
            count: videos.count,
            continuation: newToken
        )
        page.shelves = shelves
        page.shelfContinuations = page.shelfContinuations?.compactMap {
            guard $0.token == oldToken else {
                return $0
            }
            return newToken.map {
                ShelfContinuation(title: shelves[0].title, token: $0)
            }
        }
        return page
    }

    /// The TV home page pins the top of its first shelf — the same
    /// video sat first for a week, and a refresh only ever swapped
    /// the second tile. The shelf's own continuation is not pinned,
    /// so the first shelf is deepened by a few pages and shuffled;
    /// everything below it is left exactly as the server sent it.
    func expandRecommended(
        _ page: FeedPage,
        completion: @escaping (FeedPage) -> Void
    ) {
        guard let shelves = page.shelves, let first = shelves.first,
              let token = first.continuation
        else {
            completion(page)
            return
        }
        drainRecommended(
            token: token,
            pagesLeft: Self.recommendedExtraPages,
            videos: []
        ) { extra, next in
            var merged = Array(page.videos.prefix(first.count)) + extra
            var seen = Set<String>()
            merged = merged.filter { seen.insert($0.id).inserted }.shuffled()
            AppLog.home(
                "recommended expanded \(first.count) → \(merged.count) videos"
            )
            completion(Self.replacingFirstShelf(
                in: page, with: merged, oldToken: token, newToken: next
            ))
        }
    }

    /// Walks the first shelf's continuation chain, collecting videos.
    /// A failed page ends the walk with what it has — the feed still
    /// shows, just less deep.
    private func drainRecommended(
        token: String,
        pagesLeft: Int,
        videos: [Video],
        completion: @escaping ([Video], String?) -> Void
    ) {
        guard pagesLeft > 0 else {
            completion(videos, token)
            return
        }
        service.fetchNextPage(continuation: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, let page = try? result.get() else {
                    completion(videos, token)
                    return
                }
                guard let next = page.continuation else {
                    completion(videos + page.videos, nil)
                    return
                }
                self.drainRecommended(
                    token: next,
                    pagesLeft: pagesLeft - 1,
                    videos: videos + page.videos,
                    completion: completion
                )
            }
        }
    }
}
