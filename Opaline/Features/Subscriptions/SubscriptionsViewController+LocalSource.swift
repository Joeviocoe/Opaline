import UIKit

// MARK: - Local subscriptions source
//
// With no account the feed is assembled on the device from each subscribed
// channel's Atom feed. The services are already decorated, so this file is
// only about what the *screen* does differently: which empty state it shows,
// and painting from the local disk cache before the fan-out starts.

extension SubscriptionsViewController {
    /// The screen is built once at startup, so without this a subscribe made
    /// on the watch screen never reaches it — the tab keeps showing the
    /// empty state until the app is restarted, which reads exactly like
    /// subscribing not working at all.
    func observeLocalSubscriptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localSubscriptionsDidChange),
            name: LocalSubscriptionStore.didChangeNotification,
            object: nil
        )
    }

    @objc
    func localSubscriptionsDidChange() {
        guard LocalLibrary.isActive else {
            return
        }
        AppLog.library(
            "subs screen: store changed,"
                + " \(LocalSubscriptionStore.shared.count) channels"
        )
        // The channel set decides the feed, so whatever was assembled from
        // the previous set is stale.
        cache.clearLocalSubscriptionsFeed()
        if LocalSubscriptionStore.shared.count > 0 {
            isLoadingInitial = true
            spinner.startAnimating()
        }
        loadLocalInitialContent()
    }

    /// The local feed's own cached copy, kept under a separate key so a
    /// previous account's feed can never appear here.
    func loadLocalInitialContent() {
        loadSubscribedChannels()
        guard LocalSubscriptionStore.shared.count > 0 else {
            spinner.stopAnimating()
            isLoadingInitial = false
            showLocalEmptyState(true)
            tableView.reloadData()
            AppLog.library("subs screen: local, no subscriptions")
            return
        }
        showLocalEmptyState(false)
        cache.loadLocalSubscriptionsFeed { [weak self] cached in
            self?.handleLocalCachedFeed(cached)
        }
    }

    private func handleLocalCachedFeed(_ cached: FeedPage?) {
        guard let cached = cached, !cached.videos.isEmpty else {
            AppLog.library("subs screen: local cache miss, assembling")
            loadFeed()
            return
        }
        isLoadingInitial = false
        spinner.stopAnimating()
        setPage(cached)
        AppLog.library(
            "subs screen: painted \(cached.videos.count) from local cache"
        )
        // Inside the revalidate window the cache stands on its own: a
        // fan-out is one request per subscribed channel, which is not
        // something to spend on a screen that already has content.
        let age = cache.localSubscriptionsFeedAge() ?? .greatestFiniteMagnitude
        guard age >= AppCache.feedRevalidateAfter else {
            AppLog.library(
                "subs screen: cache \(Int(age))s old, skipping fan-out"
            )
            return
        }
        loadFeed()
    }

    func showLocalEmptyState(_ show: Bool) {
        if show, localEmptyState == nil {
            installLocalEmptyState()
        }
        if show {
            // "Subscribe to a channel" is wrong once they have — an empty
            // feed then means no recent uploads, or no network. Saying the
            // first would read as the subscribe having failed.
            localEmptyState?.setMessage(
                LocalSubscriptionStore.shared.count == 0
                    ? "subscriptions.local.empty".localized
                    : "subscriptions.local.noVideos".localized
            )
        }
        localEmptyState?.isHidden = !show
        if show {
            tableView.isHidden = true
        } else if localEmptyState != nil {
            tableView.isHidden = false
        }
    }

    private func installLocalEmptyState() {
        let empty = LocalEmptyStateView(
            message: "subscriptions.local.empty".localized
        )
        empty.isHidden = true
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            empty.centerYAnchor.constraint(
                equalTo: view.centerYAnchor, constant: -40
            ),
            empty.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 40
            ),
            empty.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -40
            )
        ])
        localEmptyState = empty
    }

    /// Pull-to-refresh has to drop the per-channel RSS caches, or it would
    /// be a no-op for the full 30-minute TTL.
    func refreshLocalFeed() {
        cache.clearLocalSubscriptionsFeed()
        guard let local = service as? LocalSubscriptionFeedService else {
            loadFeed()
            return
        }
        local.buildFeed(force: true) { [weak self] result in
            DispatchQueue.main.async {
                self?.applyLocalFeedResult(result)
            }
        }
    }

    private func applyLocalFeedResult(_ result: Result<FeedPage, Error>) {
        spinner.stopAnimating()
        tableView.refreshControl?.endRefreshing()
        guard case .success(let page) = result else {
            return
        }
        showLocalEmptyState(page.videos.isEmpty)
        setPage(page)
        harvestChannels(from: page)
    }
}
