import Foundation

/// The subscriptions feed, assembled on the device from each subscribed
/// channel's public Atom feed, when there is no account.
///
/// It intercepts exactly two methods and passes everything else through, so
/// `SubscriptionsViewController`'s `loadFeed`, `loadMore`, `setPage`,
/// `appendPage` and `handleFeedResult` need no changes at all — the screen
/// cannot tell which source answered.
final class LocalSubscriptionFeedService: FeedService {
    /// Videos per emitted page.
    static let pageSize = 30
    /// Sentinel continuation, generalising the same trick
    /// `SubscriptionShortsViewController` already uses for its local list.
    static let continuationPrefix = "opaline.local.subs:"

    private let inner: FeedService
    private let rss: ChannelRSSFeedService
    private let store: LocalSubscriptionStore
    private let cache: AppCache

    /// The assembled list this generation of the feed was built from, so a
    /// continuation can page through it without refetching.
    private var assembled: [Video] = []
    /// Bumped whenever the feed is rebuilt, so a continuation issued against
    /// an older list returns an empty page rather than dead-ending on
    /// indexes that no longer mean anything.
    private var generation = 0

    init(
        wrapping inner: FeedService,
        rss: ChannelRSSFeedService = ServiceContainer.channelRSS,
        store: LocalSubscriptionStore = .shared,
        cache: AppCache = .shared
    ) {
        self.inner = inner
        self.rss = rss
        self.store = store
        self.cache = cache
    }

    func fetchSubscriptionFeed(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.fetchSubscriptionFeed(completion: completion)
            return
        }
        buildFeed(force: false, completion: completion)
    }

    func fetchSubscriptionsNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        guard LocalLibrary.isActive,
              continuation.hasPrefix(
                  LocalSubscriptionFeedService.continuationPrefix
              )
        else {
            inner.fetchSubscriptionsNextPage(
                continuation: continuation,
                completion: completion
            )
            return
        }
        deliver(page: nextPage(after: continuation), to: completion)
    }

    // MARK: - Straight through

    func fetchHomeFeed(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        inner.fetchHomeFeed(completion: completion)
    }

    func fetchCategoryFeed(
        browseId: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        inner.fetchCategoryFeed(browseId: browseId, completion: completion)
    }

    func fetchNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        inner.fetchNextPage(
            continuation: continuation,
            completion: completion
        )
    }
}

// MARK: - Assembly

extension LocalSubscriptionFeedService {
    /// Rebuilds from RSS. `force` is pull-to-refresh: it drops the per-channel
    /// caches so the fan-out really goes to the network.
    func buildFeed(
        force: Bool,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        let channels = store.channels
        guard !channels.isEmpty else {
            AppLog.library("local feed: no subscriptions")
            deliver(page: FeedPage(videos: [], continuation: nil), to: completion)
            return
        }
        let withFeeds = channels.filter { $0.id.hasPrefix("UC") }
        if withFeeds.count != channels.count {
            // A channel id that is not a `UC` id has no Atom feed at all. It
            // stays in the avatar bar and simply contributes nothing.
            AppLog.library(
                "local feed: \(channels.count - withFeeds.count) of"
                    + " \(channels.count) channels have no RSS feed"
            )
        }
        fanOut(channels: withFeeds, force: force, completion: completion)
    }

    private func fanOut(
        channels: [SubscribedChannel],
        force: Bool,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        // The Subscriptions screen's own switch, not the global one: with it
        // off the long-form `UULF` feed is read instead of the channel's full
        // feed, so shorts are excluded at the source rather than filtered out
        // afterwards — fewer bytes and less parsing on the way in.
        let includeShorts = SubscriptionsShorts.isEnabled
        let started = Date()
        let byId = Dictionary(
            channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        rss.fetchRecentUploads(
            channelIds: channels.map { $0.id },
            includeShorts: includeShorts,
            force: force
        ) { [weak self] uploads in
            guard let self = self else {
                return
            }
            let ms = Int(Date().timeIntervalSince(started) * 1_000)
            let page = self.assemble(uploads: uploads, channels: byId)
            AppLog.library(
                "local feed: \(channels.count) channels,"
                    + " shorts=\(includeShorts) force=\(force),"
                    + " \(page.videos.count) videos in \(ms)ms"
            )
            self.cache.setLocalSubscriptionsFeed(page)
            completion(.success(page))
        }
    }

    /// Newest first, windowed, then cut to a page. The window matters: RSS
    /// returns ~15 entries per channel with no date bound, so without one a
    /// dormant channel turns the feed into an archive of its back catalogue.
    private func assemble(
        uploads: [String: [RSSVideoEntry]],
        channels: [String: SubscribedChannel]
    ) -> FeedPage {
        var dated: [(date: Date, video: Video)] = []
        for (channelId, entries) in uploads {
            guard let channel = channels[channelId] else {
                continue
            }
            for entry in entries {
                dated.append(
                    (
                        entry.published,
                        Video(
                            rssEntry: entry,
                            channel: channel,
                            isShort: false
                        )
                    )
                )
            }
        }
        dated.sort { $0.date > $1.date }
        let windowed = LocalFeedWindow.apply(to: dated)
        generation += 1
        assembled = windowed
        let slice = Array(
            windowed.prefix(LocalSubscriptionFeedService.pageSize)
        )
        return FeedPage(
            videos: slice,
            continuation: makeContinuation(
                offset: slice.count, total: windowed.count
            ),
            channels: Array(channels.values)
        )
    }

    private func nextPage(after continuation: String) -> FeedPage {
        let parts = continuation.split(separator: ":")
        guard parts.count == 3,
              let offset = Int(parts[1]),
              let token = Int(parts[2]),
              token == generation
        else {
            // A token from a previous generation: the list it indexed is
            // gone, so end the feed rather than serving the wrong videos.
            AppLog.library("local feed: stale continuation, ending")
            return FeedPage(videos: [], continuation: nil)
        }
        let end = min(
            offset + LocalSubscriptionFeedService.pageSize, assembled.count
        )
        guard offset < end else {
            return FeedPage(videos: [], continuation: nil)
        }
        let slice = Array(assembled[offset..<end])
        AppLog.library(
            "local feed page: \(offset)..<\(end) of \(assembled.count)"
        )
        return FeedPage(
            videos: slice,
            continuation: makeContinuation(offset: end, total: assembled.count)
        )
    }

    private func makeContinuation(offset: Int, total: Int) -> String? {
        guard offset < total else {
            return nil
        }
        return LocalSubscriptionFeedService.continuationPrefix
            + "\(offset):\(generation)"
    }

    private func deliver(
        page: FeedPage,
        to completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(.success(page))
        }
    }
}
