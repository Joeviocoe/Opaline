import Foundation

extension AppCache {
    func loadDiskValue<T: Codable>(
        _ type: T.Type,
        key: String,
        ttl: TimeInterval,
        completion: @escaping (T?) -> Void
    ) {
        guard AppCache.persistenceEnabled else {
            deliverOnMain(Optional<T>.none, completion: completion)
            return
        }
        diskQueue.async { [weak self] in
            guard let self else {
                return
            }
            let value = self.readDisk(type, key: key, ttl: ttl)
            self.deliverOnMain(value, completion: completion)
        }
    }

    // MARK: - Home
    /// Feeds are shown from cache instantly and then revalidated over the
    /// network, which rebuilds the whole screen — shelves come back in a
    /// different order every time. Screens use this age to skip that
    /// revalidation while the cache is still recent.
    func feedAge(_ feedKey: String) -> TimeInterval? {
        feedUpdatedAt(feedKey).map { Date().timeIntervalSince($0) }
    }

    /// When the cached feed was last written — screens compare it against
    /// what they are showing to notice a background refresh.
    func feedUpdatedAt(_ feedKey: String) -> Date? {
        UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Cache.feedUpdatedAt(feedKey)
        ) as? Date
    }

    func stampFeedUpdate(_ feedKey: String) {
        UserDefaults.standard.set(
            Date(),
            forKey: UserDefaultsKeys.Cache.feedUpdatedAt(feedKey)
        )
    }

    func cachedHomeFeed() -> FeedPage? {
        homeFeed
    }

    func loadHomeFeed(completion: @escaping (FeedPage?) -> Void) {
        if let feed = homeFeed {
            AppLog.cache("home mem-hit videos=\(feed.videos.count)")
            deliverOnMain(feed, completion: completion)
            return
        }
        loadDiskValue(FeedPage.self, key: "home", ttl: feedTTL) { [weak self] feed in
            guard let self else {
                return
            }
            if let feed {
                self.homeFeed = feed
                AppLog.cache("home disk-hit videos=\(feed.videos.count)")
            } else {
                AppLog.cache("home miss")
            }
            completion(feed)
        }
    }

    func setHomeFeed(_ page: FeedPage) {
        homeFeed = page
        stampFeedUpdate("home")
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: "home")
        }
        AppLog.cache("home stored videos=\(page.videos.count)")
    }

    func clearHomeFeed() {
        homeFeed = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "home")
        }
    }

    // MARK: - Subscriptions
    func cachedSubscriptionsFeed() -> FeedPage? {
        subscriptionsFeed
    }

    func loadSubscriptionsFeed(completion: @escaping (FeedPage?) -> Void) {
        if let feed = subscriptionsFeed {
            AppLog.cache("subs mem-hit videos=\(feed.videos.count)")
            deliverOnMain(feed, completion: completion)
            return
        }
        loadDiskValue(FeedPage.self, key: "subscriptions", ttl: feedTTL) { [weak self] feed in
            guard let self else {
                return
            }
            if let feed {
                self.subscriptionsFeed = feed
                AppLog.cache("subs disk-hit videos=\(feed.videos.count)")
            } else {
                AppLog.cache("subs miss")
            }
            completion(feed)
        }
    }

    func setSubscriptionsFeed(_ page: FeedPage) {
        subscriptionsFeed = page
        stampFeedUpdate("subscriptions")
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: "subscriptions")
        }
        AppLog.cache("subs stored videos=\(page.videos.count)")
    }

    func clearSubscriptionsFeed() {
        subscriptionsFeed = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "subscriptions")
        }
    }

    // MARK: - Subscribed Channels
    func loadSubscribedChannels(
        completion: @escaping ([SubscribedChannel]?) -> Void
    ) {
        if let channels = subscribedChannels {
            AppLog.cache("subChannels mem-hit count=\(channels.count)")
            deliverOnMain(channels, completion: completion)
            return
        }
        loadDiskValue(
            [SubscribedChannel].self,
            key: "subscribed_channels",
            ttl: feedTTL
        ) { [weak self] channels in
            guard let self else {
                return
            }
            if let channels {
                self.subscribedChannels = channels
                AppLog.cache("subChannels disk-hit count=\(channels.count)")
            } else {
                AppLog.cache("subChannels miss")
            }
            completion(channels)
        }
    }

    func setSubscribedChannels(_ channels: [SubscribedChannel]) {
        subscribedChannels = channels
        diskQueue.async { [weak self] in
            self?.writeDisk(channels, key: "subscribed_channels")
        }
        AppLog.cache("subChannels stored count=\(channels.count)")
    }

    func clearSubscribedChannels() {
        subscribedChannels = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "subscribed_channels")
        }
    }

    // MARK: - History
    func cachedHistoryFeed() -> FeedPage? {
        historyFeed
    }

    func loadHistoryFeed(completion: @escaping (FeedPage?) -> Void) {
        if let feed = historyFeed {
            deliverOnMain(feed, completion: completion)
            return
        }
        loadDiskValue(FeedPage.self, key: "history", ttl: feedTTL) { [weak self] feed in
            guard let self else {
                return
            }
            if let feed {
                self.historyFeed = feed
            }
            completion(feed)
        }
    }

    func setHistoryFeed(_ page: FeedPage) {
        historyFeed = page
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: "history")
        }
    }

    func clearHistoryFeed() {
        historyFeed = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "history")
        }
    }

    // MARK: - Clear All
    func clearAllDiskCache() {
        let channelInfoKeys = channelInfoMemory.keys
        homeFeed = nil
        subscriptionsFeed = nil
        subscribedChannels = nil
        historyFeed = nil
        channelInfoMemory.removeAll()
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "home")
            self?.deleteDisk(key: "subscriptions")
            self?.deleteDisk(key: "subscribed_channels")
            self?.deleteDisk(key: "history")
            channelInfoKeys.forEach {
                self?.deleteDisk(key: "channel_info_\($0)")
            }
        }
    }
}
