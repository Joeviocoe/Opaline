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
                self.endRefreshing()
                switch result {
                case .success(let page):
                    AppLog.home("network fetch done \(ms)ms videos=\(page.videos.count)")
                    self.applyFreshFeed(page)
                case .failure(let err):
                    AppLog.home("network fetch failed \(ms)ms: \(err)")
                    self.endChipDiscovery()
                    // Keep cached/stale content when revalidation
                    // fails offline — only blank screens get the error.
                    if self.videoCount == 0 {
                        self.setPage(FeedPage(videos: [], continuation: nil))
                        self.showFeedError()
                    }
                }
            }
        }
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
