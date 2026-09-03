import Foundation

/// Disk cache for the locally assembled subscriptions feed.
///
/// Its own key, deliberately separate from `subscriptions`: a previous
/// account's cached feed must never surface to a signed-out session, and
/// two keys is a stronger guarantee of that than any clearing discipline.
///
/// This is not an optimisation. Assembling the feed means one Atom request
/// per subscribed channel — around 5s for 60 channels and 17s for 200 — so
/// without it every cold launch would sit on a spinner while it refetched
/// something it already had.
extension AppCache {
    static let localSubscriptionsKey = "local_subscriptions"

    func loadLocalSubscriptionsFeed(
        completion: @escaping (FeedPage?) -> Void
    ) {
        loadDiskValue(
            FeedPage.self,
            key: AppCache.localSubscriptionsKey,
            ttl: feedTTL
        ) { feed in
            AppLog.library(
                "local feed cache: "
                    + (feed.map { "hit videos=\($0.videos.count)" }
                        ?? "miss")
            )
            completion(feed)
        }
    }

    func setLocalSubscriptionsFeed(_ page: FeedPage) {
        stampFeedUpdate(AppCache.localSubscriptionsKey)
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: AppCache.localSubscriptionsKey)
        }
        AppLog.library("local feed stored videos=\(page.videos.count)")
    }

    func clearLocalSubscriptionsFeed() {
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: AppCache.localSubscriptionsKey)
        }
        AppLog.library("local feed cleared")
    }

    /// How stale the cached local feed is, so a cold launch inside the
    /// window can skip firing one request per subscribed channel.
    func localSubscriptionsFeedAge() -> TimeInterval? {
        feedAge(AppCache.localSubscriptionsKey)
    }
}
