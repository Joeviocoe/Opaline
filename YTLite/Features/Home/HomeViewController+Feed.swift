import UIKit

// MARK: - Feed loading

extension HomeViewController {
    func setupToolbar() {
        ToolbarManager.shared.install(in: self)
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
                self.setPage(self.enqueueShelves(from: cachedPage))
                // Revalidating replaces the whole feed — YouTube reorders
                // shelves on every request, so the screen visibly rebuilds
                // and thumbnails reload. Skip it while the cache is recent;
                // background refresh keeps it that way, pull-to-refresh
                // forces it, and a stale continuation triggers it lazily.
                let age = self.cache.feedAge("home") ?? .greatestFiniteMagnitude
                guard age >= AppCache.feedRevalidateAfter else {
                    AppLog.home("cache is \(Int(age / 60))m old → no revalidation")
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
        startFreshSession()
        setPage(enqueueShelves(from: page))
        rebuildChips()
        applyPendingChipReselect()
        continueChipPrefetchIfNeeded()
    }
}
