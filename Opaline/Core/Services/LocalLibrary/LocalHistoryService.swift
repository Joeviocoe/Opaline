import Foundation

/// Watch history from the local store when there is no account.
///
/// Its real consumer is the **new-content dots**: `refreshNewContentDots`
/// asks `historyService.fetchHistory` for what has been watched and unions
/// it with the ids seen this session, so decorating this is what makes the
/// dots work signed out at all.
///
/// The History *screen* deliberately does not come through here — it
/// branches to the store directly. Paging takes a live OAuth token as a
/// parameter and delete rides an opaque server-issued feedback token, so a
/// local page dressed up as an account page would be wrong in two ways that
/// only show up after the user taps something.
final class LocalHistoryService: HistoryService {
    private let inner: HistoryService
    private let store: LocalHistoryStore

    init(
        wrapping inner: HistoryService,
        store: LocalHistoryStore = .shared
    ) {
        self.inner = inner
        self.store = store
    }

    func fetchHistory(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.fetchHistory(completion: completion)
            return
        }
        let videos = store.videos
        AppLog.library("local history fetch: \(videos.count) videos")
        DispatchQueue.main.async {
            completion(
                .success(FeedPage(videos: videos, continuation: nil))
            )
        }
    }

    func fetchHistoryNextPage(
        continuation: String,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.fetchHistoryNextPage(
                continuation: continuation,
                token: token,
                completion: completion
            )
            return
        }
        // The local store is handed over whole in one page, so there is
        // never a second one.
        DispatchQueue.main.async {
            completion(
                .success(FeedPage(videos: [], continuation: nil))
            )
        }
    }
}
