import Foundation

/// One video entry from a channel's public Atom feed.
struct RSSVideoEntry {
    let videoId: String
    let published: Date
}

/// Fetches the public per-channel Atom feeds (`/feeds/videos.xml`) used
/// to detect fresh uploads for the new-content dots (issue #13).
/// Anonymous, chronological, immune to the relevance ranking that broke
/// the TVHTML5 subscriptions feed as a freshness signal.
protocol ChannelRSSFeedService: AnyObject {
    /// Fetches recent uploads for every channel id; failed channels are
    /// omitted from the result. When `includeShorts` is false the
    /// long-form-only `UULF` playlist feed is used (full feed as
    /// fallback). Completion fires on the main queue.
    func fetchRecentUploads(
        channelIds: [String],
        includeShorts: Bool,
        completion: @escaping ([String: [RSSVideoEntry]]) -> Void
    )
}

final class ChannelRSSService: ChannelRSSFeedService {
    private struct CacheSlot {
        let entries: [RSSVideoEntry]
        let fetchedAt: Date
    }

    /// Per-channel snapshots younger than this are served from memory.
    static let cacheTTL: TimeInterval = 30 * 60

    /// Sliding-window cap so a cold start with many subscriptions
    /// doesn't burst dozens of connections and starve the feed request.
    static let maxConcurrentFetches = 4

    private let transport: HTTPTransport
    private let queue = DispatchQueue(label: "ChannelRSSService")
    private var cache: [String: CacheSlot] = [:]

    init(transport: HTTPTransport = ServiceContainer.mediaTransport) {
        self.transport = transport
    }

    func fetchRecentUploads(
        channelIds: [String],
        includeShorts: Bool,
        completion: @escaping ([String: [RSSVideoEntry]]) -> Void
    ) {
        queue.async {
            self.fetchOnQueue(
                channelIds: channelIds,
                includeShorts: includeShorts,
                completion: completion
            )
        }
    }
}

/// Mutable state of one `fetchRecentUploads` fan-out; only touched on
/// the service queue.
private final class FetchBatch {
    var pending: [String]
    var results: [String: [RSSVideoEntry]]
    var active = 0
    let includeShorts: Bool
    let completion: ([String: [RSSVideoEntry]]) -> Void

    init(
        pending: [String],
        results: [String: [RSSVideoEntry]],
        includeShorts: Bool,
        completion: @escaping ([String: [RSSVideoEntry]]) -> Void
    ) {
        self.pending = pending
        self.results = results
        self.includeShorts = includeShorts
        self.completion = completion
    }
}

// MARK: - Private Helpers

private extension ChannelRSSService {
    /// Keyed per mode so toggling the Shorts setting never serves
    /// entries fetched for the other feed variant.
    func cacheKey(_ channelId: String, includeShorts: Bool) -> String {
        (includeShorts ? "all|" : "lf|") + channelId
    }

    /// Splits ids into cache hits and stale/missing ones. On-queue.
    func partitionCached(
        _ channelIds: [String],
        includeShorts: Bool
    ) -> (cached: [String: [RSSVideoEntry]], stale: [String]) {
        var cached: [String: [RSSVideoEntry]] = [:]
        var stale: [String] = []
        let now = Date()
        for id in Set(channelIds) {
            if let slot = cache[cacheKey(id, includeShorts: includeShorts)],
               now.timeIntervalSince(slot.fetchedAt)
               < ChannelRSSService.cacheTTL {
                cached[id] = slot.entries
            } else {
                stale.append(id)
            }
        }
        return (cached, stale)
    }

    func fetchOnQueue(
        channelIds: [String],
        includeShorts: Bool,
        completion: @escaping ([String: [RSSVideoEntry]]) -> Void
    ) {
        let (cached, stale) = partitionCached(
            channelIds,
            includeShorts: includeShorts
        )
        guard !stale.isEmpty else {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        AppLog.subs("rss: fetching \(stale.count) channels")
        let batch = FetchBatch(
            pending: stale,
            results: cached,
            includeShorts: includeShorts,
            completion: completion
        )
        startNextFetches(in: batch)
    }

    /// Keeps at most `maxConcurrentFetches` requests in flight,
    /// starting the next one as each completes. On-queue.
    func startNextFetches(in batch: FetchBatch) {
        while batch.active < ChannelRSSService.maxConcurrentFetches,
              !batch.pending.isEmpty {
            let id = batch.pending.removeFirst()
            batch.active += 1
            fetchChannel(id, includeShorts: batch.includeShorts) { entries in
                batch.active -= 1
                if let entries {
                    let key = self.cacheKey(
                        id,
                        includeShorts: batch.includeShorts
                    )
                    self.cache[key] = CacheSlot(
                        entries: entries,
                        fetchedAt: Date()
                    )
                    batch.results[id] = entries
                }
                self.startNextFetches(in: batch)
            }
        }
        if batch.active == 0, batch.pending.isEmpty {
            let results = batch.results
            DispatchQueue.main.async { batch.completion(results) }
        }
    }

    /// Long-form (`UULF`) feed first when Shorts are hidden; the full
    /// feed is the fallback for channels where that playlist 404s.
    /// Calls back on `queue`; nil when both variants fail.
    func fetchChannel(
        _ channelId: String,
        includeShorts: Bool,
        completion: @escaping ([RSSVideoEntry]?) -> Void
    ) {
        let fullFeedURL = AppURLs.YouTube.channelRSSFeedURL(
            channelId: channelId
        )
        guard !includeShorts,
              let longFormURL = AppURLs.YouTube.channelLongFormRSSFeedURL(
                  channelId: channelId
              )
        else {
            fetchFeed(url: fullFeedURL, completion: completion)
            return
        }
        fetchFeed(url: longFormURL) { entries in
            if let entries {
                completion(entries)
            } else {
                self.fetchFeed(url: fullFeedURL, completion: completion)
            }
        }
    }

    /// Calls back on `queue`; nil on transport or parse failure.
    func fetchFeed(
        url: URL?,
        completion: @escaping ([RSSVideoEntry]?) -> Void
    ) {
        guard let url else {
            completion(nil)
            return
        }
        let request = HTTPRequest(
            method: .get,
            url: url,
            sendsCookies: false
        )
        transport.send(request, cancellationToken: nil) { result in
            self.queue.async {
                guard case .success(let response) = result,
                      response.status == 200
                else {
                    completion(nil)
                    return
                }
                completion(ChannelRSSParser.parse(response.data))
            }
        }
    }
}
