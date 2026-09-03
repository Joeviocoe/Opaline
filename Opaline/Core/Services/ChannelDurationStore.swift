import Foundation

/// Durations for videos that arrived without one.
///
/// The subscriptions feed is assembled from each channel's Atom feed, and
/// Atom carries no duration — only `yt:videoId`, title, published date and
/// `media:statistics views`. Verified against a live feed, not assumed.
///
/// The channel's Videos tab does carry it, in the same
/// `thumbnailOverlayTimeStatusRenderer` the rest of the app already parses,
/// and that browse is anonymous — the same one the channel screen uses.
///
/// **The cost is per channel, not per video.** One request returns ~30
/// videos with their durations, so a single fetch fills in every row that
/// channel contributed to the feed. With a large subscription list the bill
/// is bounded by how many distinct channels are actually scrolled past, not
/// by how many videos are on screen.
final class ChannelDurationStore {
    static let shared = ChannelDurationStore()

    /// Two, not three: each response is a browse payload an order of
    /// magnitude heavier than the Atom feed, parsed on an A5X while
    /// thumbnails are still decoding. `ChannelInfoStore` uses three for a
    /// much lighter call.
    private static let maxConcurrentFetches = 2
    /// A published video's length never changes, so this can cache for as
    /// long as channel info does.
    private static let ttl: TimeInterval = 30 * 24 * 60 * 60

    private var tabService: ChannelTabService?
    private let queue = DispatchQueue(label: "com.ytvlite.channel-durations")
    /// videoId -> duration, per channel.
    private var cache: [String: [String: String]] = [:]
    /// Channels already asked for and found wanting, so a channel whose tab
    /// genuinely has nothing useful is not re-fetched on every settle.
    private var missing: Set<String> = []
    private var pending: Set<String> = []
    private var activeFetches = 0
    private var waiting: [String] = []

    private init() {}

    func configure(tabService: ChannelTabService) {
        self.tabService = tabService
    }

    /// Cached durations for a channel, or nil when it has not been fetched.
    /// Synchronous and cheap: callers are in a layout path.
    func durations(forChannel channelId: String) -> [String: String]? {
        queue.sync { cache[channelId] }
    }

    /// Fetches unless the channel is cached, already in flight, or known to
    /// have nothing. `onReady` fires on the main queue, once, per fetch.
    func prefetch(channelId: String, onReady: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            // Each of these returns is logged: a prefetch that quietly
            // decides to do nothing is indistinguishable from one that was
            // never called, and that ambiguity has already cost a build.
            if self.cache[channelId] != nil {
                AppLog.subs("durations \(channelId): already cached")
                DispatchQueue.main.async { onReady() }
                return
            }
            guard !self.pending.contains(channelId) else {
                AppLog.subs("durations \(channelId): already in flight")
                return
            }
            guard !self.missing.contains(channelId) else {
                AppLog.subs("durations \(channelId): known to have none")
                return
            }
            if let disk = self.loadFromDisk(channelId) {
                self.cache[channelId] = disk
                AppLog.subs(
                    "durations \(channelId): \(disk.count) from disk"
                )
                DispatchQueue.main.async { onReady() }
                return
            }
            self.pending.insert(channelId)
            guard self.activeFetches < Self.maxConcurrentFetches else {
                self.waiting.append(channelId)
                AppLog.subs("durations \(channelId): queued")
                return
            }
            self.startFetch(channelId, onReady: onReady)
        }
    }
}

// MARK: - Fetching

private extension ChannelDurationStore {
    /// Call on `queue`.
    func startFetch(_ channelId: String, onReady: @escaping () -> Void) {
        guard let tabService = tabService else {
            pending.remove(channelId)
            // Only possible if configure() never ran — worth saying out
            // loud rather than silently doing nothing forever.
            AppLog.subs("durations \(channelId): NO TAB SERVICE")
            return
        }
        activeFetches += 1
        AppLog.subs("durations \(channelId): fetching tab")
        tabService.fetchChannelTab(
            channelId: channelId,
            params: ChannelTabParams.videos
        ) { [weak self] result in
            self?.queue.async {
                self?.store(result, channelId: channelId)
                DispatchQueue.main.async { onReady() }
                self?.startNextWaiting(onReady: onReady)
            }
        }
    }

    /// Call on `queue`.
    func store(
        _ result: Result<ChannelTabPage, Error>, channelId: String
    ) {
        activeFetches -= 1
        pending.remove(channelId)
        guard case .success(let page) = result else {
            // Not cached as missing: a transport failure says nothing about
            // whether the channel has durations, and marking it would make
            // one bad moment permanent.
            AppLog.subs("durations \(channelId): fetch failed")
            return
        }
        var map: [String: String] = [:]
        for video in page.feedPage.videos {
            if let duration = video.duration, !duration.isEmpty {
                map[video.id] = duration
            }
        }
        guard !map.isEmpty else {
            missing.insert(channelId)
            AppLog.subs("durations \(channelId): none in tab")
            return
        }
        cache[channelId] = map
        writeToDisk(map, channelId: channelId)
        AppLog.subs("durations \(channelId): \(map.count) videos")
    }

    /// Call on `queue`.
    func startNextWaiting(onReady: @escaping () -> Void) {
        guard activeFetches < Self.maxConcurrentFetches, !waiting.isEmpty
        else {
            return
        }
        startFetch(waiting.removeFirst(), onReady: onReady)
    }

    func diskKey(_ channelId: String) -> String {
        "channel_durations_\(channelId)"
    }

    func loadFromDisk(_ channelId: String) -> [String: String]? {
        AppCache.shared.readDisk(
            [String: String].self, key: diskKey(channelId), ttl: Self.ttl
        )
    }

    func writeToDisk(_ map: [String: String], channelId: String) {
        AppCache.shared.diskQueue.async {
            AppCache.shared.writeDisk(map, key: self.diskKey(channelId))
        }
    }
}
