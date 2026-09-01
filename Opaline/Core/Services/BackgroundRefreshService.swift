import Foundation

/// Refreshes the home and subscriptions feeds from a background fetch wake-up,
/// so the cache is warm the next time either screen opens.
///
/// Not wired up here — call `refresh(completion:)` from
/// `AppDelegate+Notifications.swift`'s
/// `application(_:performFetchWithCompletionHandler:)`, alongside the
/// existing `UpdateNotificationService.shared.checkIfNeeded` call. The two
/// share the ~30s background execution window.
final class BackgroundRefreshService {
    static let shared = BackgroundRefreshService()

    /// Self-imposed budget, well under iOS's ~30s background fetch window
    /// (shared with the notification check running alongside this).
    private static let budget: TimeInterval = 20

    private let feedService: FeedService
    private let historyService: HistoryService
    private let cache: AppCache

    init(
        feedService: FeedService = ServiceContainer.feed,
        historyService: HistoryService = ServiceContainer.history,
        cache: AppCache = .shared
    ) {
        self.feedService = feedService
        self.historyService = historyService
        self.cache = cache
    }

    /// Fills the caches the *other* tabs read on their first open, so
    /// arriving there doesn't start with a spinner. Runs one request at
    /// a time and only once the home feed has settled — on a slow link
    /// a parallel burst would just delay the screen the user is looking
    /// at (the same reason the subscription dots defer their fetches).
    func warmSecondaryCaches() {
        guard !OAuthClient.shared.isAnonymous else {
            return
        }
        fetchSubscriptions(into: nil) { [weak self] in
            self?.warmHistory()
        }
    }

    private func warmHistory() {
        historyService.fetchHistory { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let page) = result else {
                    AppLog.cache("warm: history failed")
                    return
                }
                self?.cache.setHistoryFeed(page)
                AppLog.cache("warm: history ok videos=\(page.videos.count)")
            }
        }
    }

    /// Fetches both feeds concurrently and stores whatever comes back.
    /// Completes with `true` iff at least one feed actually refreshed —
    /// callers map that to `.newData`/`.noData`, which iOS uses to budget
    /// future background time, so a false positive would be self-defeating.
    func refresh(completion: @escaping (Bool) -> Void) {
        guard !OAuthClient.shared.isAnonymous else {
            AppLog.cache("background refresh: signed out → skip")
            completion(false)
            return
        }
        let t0 = Date()
        AppLog.cache("background refresh: start")
        let state = RefreshState(completion: completion, startedAt: t0)
        fetchHome(into: state)
        fetchSubscriptions(into: state)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.budget) { [weak self] in
            self?.finish(state, reason: "budget")
        }
    }

    private func fetchHome(into state: RefreshState) {
        feedService.fetchHomeFeed { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.cache.setHomeFeed(page)
                    AppLog.cache("background refresh: home ok videos=\(page.videos.count)")
                    state.homeSucceeded = true
                case .failure(let error):
                    AppLog.cache("background refresh: home failed \(error)")
                }
                self?.finishOne(state)
            }
        }
    }

    /// `state` is nil when warming caches in the foreground — same
    /// fetch-and-store, no background-fetch bookkeeping.
    private func fetchSubscriptions(
        into state: RefreshState?,
        then next: (() -> Void)? = nil
    ) {
        feedService.fetchSubscriptionFeed { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.cache.setSubscriptionsFeed(page)
                    AppLog.cache("subs cached videos=\(page.videos.count)")
                    state?.subsSucceeded = true
                case .failure(let error):
                    AppLog.cache("subs fetch failed \(error)")
                }
                if let state = state {
                    self?.finishOne(state)
                }
                next?()
            }
        }
    }

    private func finishOne(_ state: RefreshState) {
        state.completedCount += 1
        guard state.completedCount >= 2 else {
            return
        }
        finish(state, reason: "both feeds")
    }

    private func finish(_ state: RefreshState, reason: String) {
        guard !state.isFinished else {
            return
        }
        state.isFinished = true
        let ms = Int(Date().timeIntervalSince(state.startedAt) * 1_000)
        let success = state.homeSucceeded || state.subsSucceeded
        AppLog.cache(
            "background refresh: done via \(reason) in \(ms)ms "
                + "home=\(state.homeSucceeded) subs=\(state.subsSucceeded)"
        )
        state.completion(success)
    }
}

/// Mutable bookkeeping for one `refresh(completion:)` call, always touched
/// on the main queue — avoids a lock for what's effectively a two-callback
/// join with a timeout race.
private final class RefreshState {
    let completion: (Bool) -> Void
    let startedAt: Date
    var completedCount = 0
    var homeSucceeded = false
    var subsSucceeded = false
    var isFinished = false

    init(completion: @escaping (Bool) -> Void, startedAt: Date) {
        self.completion = completion
        self.startedAt = startedAt
    }
}
