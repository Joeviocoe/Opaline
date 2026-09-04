import Foundation

/// The subscriptions feed, assembled on the device from each subscribed
/// channel's own Videos tab, when there is no account.
///
/// It was built on the public Atom feeds until those stopped being usable:
/// the `UULF` long-form playlist that made the Shorts switch work now fails
/// for every channel, and the resulting fallback doubled the request count
/// into a burst that got most channels throttled. See `LocalChannelUploads`.
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
    private let uploads: LocalChannelUploads
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
        uploads: LocalChannelUploads = LocalChannelUploads(),
        store: LocalSubscriptionStore = .shared,
        cache: AppCache = .shared
    ) {
        self.inner = inner
        self.uploads = uploads
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
    /// Rebuilds from each channel's Videos tab, one channel at a time.
    /// `force` is pull-to-refresh: it drops the per-channel cache so the walk
    /// really goes to the network.
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
        if force {
            uploads.invalidate()
        }
        walk(channels: channels, completion: completion)
    }

    private func walk(
        channels: [SubscribedChannel],
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        // The Subscriptions screen's own switch, not the global one. With it
        // off only the Videos tab is read, which excludes Shorts by
        // construction rather than by the `UULF` playlist trick that stopped
        // resolving; with it on the Shorts tab is read too and everything
        // from it is marked `isShort`.
        let includeShorts = SubscriptionsShorts.isEnabled
        let started = Date()
        uploads.fetch(
            channelIds: channels.map { $0.id },
            includeShorts: includeShorts
        ) { [weak self] byChannel in
            guard let self = self else {
                return
            }
            let ms = Int(Date().timeIntervalSince(started) * 1_000)
            guard !byChannel.isEmpty else {
                self.reportNothingAnswered(
                    asked: channels.count, ms: ms, to: completion
                )
                return
            }
            let page = self.assemble(uploads: byChannel, channels: channels)
            AppLog.library(
                "local feed: \(byChannel.count)/\(channels.count) answered,"
                    + " shorts=\(includeShorts),"
                    + " \(page.videos.count) videos in \(ms)ms"
            )
            self.cache.setLocalSubscriptionsFeed(page)
            completion(.success(page))
        }
    }

    /// Not one channel came back with anything.
    ///
    /// A live channel's Atom feed effectively always has entries, so zero
    /// across the whole fan-out is the network failing — not a library with
    /// nothing recent in it. The two are indistinguishable by the time they
    /// reach the screen, and guessing "empty" swaps a good feed for "No
    /// recent videos" and writes the emptiness into the disk cache on the
    /// way out, so the next cold launch starts with nothing too.
    ///
    /// Reporting failure instead leaves both the screen and the cache alone.
    private func reportNothingAnswered(
        asked: Int,
        ms: Int,
        to completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        AppLog.library(
            "local feed: none of \(asked) channels answered in \(ms)ms"
                + " — refresh failed, keeping what we had"
        )
        completion(.failure(LocalFeedError.noChannelAnswered))
    }

    /// Newest first, windowed, then cut to a page. The window matters: a tab
    /// returns ~30 videos per channel with no date bound, so without one a
    /// dormant channel turns the feed into an archive of its back catalogue.
    private func assemble(
        uploads: [String: [Video]],
        channels: [SubscribedChannel]
    ) -> FeedPage {
        let entries = feedEntries(uploads: uploads, channels: channels)
        LocalChannelActivity.record(latestUploads(in: entries))
        let ordered = LocalFeedOrder.sorted(entries)
        let windowed = LocalFeedWindow.apply(
            to: ordered.map { (date: $0.date, video: $0.video) }
        )
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
            // Ordered most-recent-upload first, which the store can answer
            // because the line above just told it. Every subscription, not
            // only the ones with an Atom feed: the bar shows them all, and
            // the screen takes this list as primary when it merges.
            channels: store.channels
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

/// Why a local rebuild produced nothing. Distinguishing this from an empty
/// feed is the whole point — an empty `FeedPage` tells the screen "you have
/// nothing recent", which is a lie when the truth is "I could not reach
/// anything".
enum LocalFeedError: Error {
    case noChannelAnswered
}
