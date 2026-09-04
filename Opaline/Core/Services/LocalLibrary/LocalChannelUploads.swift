import Foundation

/// Recent uploads per channel, from each channel's own Videos tab.
///
/// Replaces the Atom fan-out this feed used to be built from. Three things
/// forced the change, all of them measured rather than assumed:
///
/// - The `UULF` long-form playlist feed — the only way Atom could exclude
///   Shorts — now fails for **every** channel, so the Shorts switch had no
///   mechanism behind it and each channel silently cost two requests.
/// - Four-way concurrency plus a second, uncoordinated fan-out for the
///   new-content dots put ~60 requests in flight inside 1.2s, and most of
///   them failed: `local feed: 2/15 answered`, repeatedly.
/// - A failed fetch was cached as an empty result for five minutes, so one
///   bad burst silenced 13 channels for the next several refreshes.
///
/// So: **one channel at a time, spaced out, and a failure is never mistaken
/// for an empty channel.** Slower on paper and far better in practice — a
/// browse that answers beats an Atom feed that doesn't. It also returns ~30
/// videos where Atom returned ~15, with durations and live status already
/// parsed, which is what let the whole duration-enrichment pass be deleted.
///
/// The cost this pays is date precision: browse gives `publishedTimeText`
/// ("3 hours ago"), not Atom's exact timestamp. See `LocalFeedOrder`.
final class LocalChannelUploads {
    /// Gap between channels. The point is not politeness in the abstract —
    /// it is that the burst is what got the old fan-out throttled.
    static let requestSpacing: TimeInterval = 0.3
    /// A channel's uploads are good for this long. Matches what the Atom
    /// service used, and a channel does not publish twice in half an hour.
    static let cacheTTL: TimeInterval = 30 * 60

    private struct Slot {
        let videos: [Video]
        let fetchedAt: Date
    }

    private let tabs: ChannelTabService
    /// Keyed by channel *and* whether Shorts were folded in. Without the
    /// variant, flipping the Shorts switch would serve back the other
    /// variant's videos for the rest of the TTL — and the toggle reloads the
    /// feed without forcing, so nothing else would catch it.
    private var cache: [String: Slot] = [:]
    /// The traversal currently running, if any. Callers that arrive while it
    /// is going join it instead of starting a second one.
    private var walkInProgress: ChannelUploadsWalk?
    /// A request that arrived mid-walk asking for the other Shorts variant,
    /// to run once the current walk is done.
    private var queuedRewalk: (
        ids: [String], includeShorts: Bool,
        completion: ([String: [Video]]) -> Void
    )?

    private func cacheKey(_ channelId: String, includeShorts: Bool) -> String {
        includeShorts ? channelId + "+shorts" : channelId
    }

    init(tabs: ChannelTabService = ServiceContainer.channelTabs) {
        self.tabs = tabs
    }

    func invalidate() {
        cache.removeAll()
        AppLog.library("channel uploads: cache cleared")
    }

    /// Walks `channelIds` one at a time and calls back once, on the main
    /// queue, with everything that answered. Channels that failed are simply
    /// absent — never present-but-empty, which is the distinction the old
    /// negative cache lost.
    ///
    /// **Concurrent calls join the walk already running rather than starting
    /// a second one.** Two callers overlap routinely — a pull-to-refresh and
    /// the stale-cache revalidation that fires when the tab is reopened — and
    /// without this they double the request count and throttle each other:
    /// measured at 62 of 99 fetches returning nothing, and the walk stretching
    /// from 17.7s to 32s. Everyone waiting gets the same result, which is
    /// what they each asked for anyway.
    func fetch(
        channelIds: [String],
        includeShorts: Bool,
        completion: @escaping ([String: [Video]]) -> Void
    ) {
        if let running = walkInProgress {
            join(running, channelIds: channelIds,
                 includeShorts: includeShorts, completion: completion)
            return
        }
        let walk = ChannelUploadsWalk(
            remaining: channelIds,
            total: channelIds.count,
            includeShorts: includeShorts,
            completion: completion
        )
        walkInProgress = walk
        step(walk)
    }

    /// A caller arriving mid-walk. Same Shorts variant: wait for the result
    /// that is already coming. Different variant (the toggle was flipped):
    /// remember it and re-walk once, because the running walk is reading the
    /// wrong tabs for that caller and joining it would silently ignore the
    /// setting change.
    private func join(
        _ running: ChannelUploadsWalk,
        channelIds: [String],
        includeShorts: Bool,
        completion: @escaping ([String: [Video]]) -> Void
    ) {
        guard includeShorts == running.includeShorts else {
            AppLog.library("channel uploads: variant changed, queued re-walk")
            queuedRewalk = (channelIds, includeShorts, completion)
            return
        }
        AppLog.library("channel uploads: joined walk in progress")
        running.waiters.append(completion)
    }
}

// MARK: - Walking the list

private extension LocalChannelUploads {
    func step(_ walk: ChannelUploadsWalk) {
        guard !walk.remaining.isEmpty else {
            finish(walk)
            return
        }
        let channelId = walk.remaining.removeFirst()
        load(
            channelId: channelId, includeShorts: walk.includeShorts
        ) { [weak self] videos in
            if let videos = videos, !videos.isEmpty {
                walk.results[channelId] = videos
            }
            guard let self = self else {
                return
            }
            guard !walk.remaining.isEmpty else {
                self.finish(walk)
                return
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + LocalChannelUploads.requestSpacing
            ) {
                self.step(walk)
            }
        }
    }

    func finish(_ walk: ChannelUploadsWalk) {
        let ms = Int(Date().timeIntervalSince(walk.started) * 1_000)
        AppLog.library(
            "channel uploads: \(walk.results.count)/\(walk.total)"
                + " answered in \(ms)ms, \(walk.waiters.count) joined"
        )
        walkInProgress = nil
        walk.completion(walk.results)
        for waiter in walk.waiters {
            waiter(walk.results)
        }
        guard let queued = queuedRewalk else {
            return
        }
        queuedRewalk = nil
        fetch(
            channelIds: queued.ids,
            includeShorts: queued.includeShorts,
            completion: queued.completion
        )
    }
}

// MARK: - One channel

private extension LocalChannelUploads {
    /// nil means the fetch failed. An empty array would mean the channel
    /// genuinely has nothing, and the two must not be conflated.
    func load(
        channelId: String,
        includeShorts: Bool,
        completion: @escaping ([Video]?) -> Void
    ) {
        let key = cacheKey(channelId, includeShorts: includeShorts)
        if let slot = cache[key],
           Date().timeIntervalSince(slot.fetchedAt)
               < LocalChannelUploads.cacheTTL {
            completion(slot.videos)
            return
        }
        loadTab(channelId: channelId, params: ChannelTabParams.videos) {
            [weak self] longForm in
            guard let self = self else {
                completion(nil)
                return
            }
            guard includeShorts else {
                self.store(longForm, for: key)
                completion(longForm)
                return
            }
            self.appendShorts(
                to: longForm,
                channelId: channelId,
                key: key,
                completion: completion
            )
        }
    }

    /// The Shorts tab, folded in only when the switch is on. Everything it
    /// returns is `isShort` by definition — which is what `UUSH` was for,
    /// except this one actually resolves.
    func appendShorts(
        to longForm: [Video]?,
        channelId: String,
        key: String,
        completion: @escaping ([Video]?) -> Void
    ) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LocalChannelUploads.requestSpacing
        ) { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            self.loadTab(
                channelId: channelId, params: ChannelTabParams.shorts
            ) { shorts in
                let marked = (shorts ?? []).map { video -> Video in
                    var copy = video
                    copy.isShort = true
                    return copy
                }
                // A failed Shorts tab must not discard the long-form videos
                // that already arrived.
                guard longForm != nil || !marked.isEmpty else {
                    completion(nil)
                    return
                }
                let combined = (longForm ?? []) + marked
                self.store(combined, for: key)
                completion(combined)
            }
        }
    }

    func store(_ videos: [Video]?, for key: String) {
        guard let videos = videos else {
            return
        }
        cache[key] = Slot(videos: videos, fetchedAt: Date())
    }

    func loadTab(
        channelId: String,
        params: String,
        completion: @escaping ([Video]?) -> Void
    ) {
        let started = Date()
        tabs.fetchChannelTab(
            channelId: channelId, params: params
        ) { result in
            DispatchQueue.main.async {
                let ms = Int(Date().timeIntervalSince(started) * 1_000)
                switch result {
                case .success(let page):
                    AppLog.library(
                        "channel uploads \(channelId):"
                            + " \(page.feedPage.videos.count) videos in \(ms)ms"
                    )
                    completion(page.feedPage.videos)
                case .failure(let error):
                    // Logged, and deliberately not cached: the next refresh
                    // retries instead of reading back a fabricated empty.
                    AppLog.library(
                        "channel uploads \(channelId): FAILED in \(ms)ms"
                            + " — \(error)"
                    )
                    completion(nil)
                }
            }
        }
    }
}
