import Foundation

/// Routes subscribe/unsubscribe to the local store when there is no account,
/// and to the server when there is.
///
/// Same shape as `OfflineWatchService`: a decorator wrapping the real
/// service, registered once in `ServiceContainer`, so no call site changes.
/// Only the two subscription verbs are intercepted — `sendLike`,
/// `sendFeedback` and `editPlaylist` pass straight through and still fail
/// signed out, which is correct. There is nothing local about a like.
final class LocalEngagementService: EngagementService {
    private let inner: EngagementService
    private let store: LocalSubscriptionStore

    init(
        wrapping inner: EngagementService,
        store: LocalSubscriptionStore = .shared
    ) {
        self.inner = inner
        self.store = store
    }

    func subscribeToChannel(
        channelId: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.subscribeToChannel(
                channelId: channelId,
                cancellationToken: cancellationToken,
                completion: completion
            )
            return
        }
        let identity = LocalChannelIdentity.shared.identity(for: channelId)
        let stored = store.subscribe(
            channelId: channelId,
            title: identity.title,
            avatarURL: identity.avatarURL
        )
        AppLog.library(
            "local subscribe \(channelId) identity=\(identity.source)"
                + " stored=\(stored)"
        )
        deliver(stored: stored, completion: completion)
    }

    func unsubscribeFromChannel(
        channelId: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.unsubscribeFromChannel(
                channelId: channelId,
                cancellationToken: cancellationToken,
                completion: completion
            )
            return
        }
        let removed = store.unsubscribe(channelId: channelId)
        AppLog.library(
            "local unsubscribe \(channelId) removed=\(removed)"
        )
        // Removing something that was not there is not a failure: the
        // button's optimistic flip should stand either way.
        deliver(stored: true, completion: completion)
    }

    // MARK: - Straight through

    func sendLike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        inner.sendLike(videoId: videoId, completion: completion)
    }

    func sendDislike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        inner.sendDislike(videoId: videoId, completion: completion)
    }

    func removeLike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        inner.removeLike(videoId: videoId, completion: completion)
    }

    func editPlaylist(
        playlistId: String,
        actions: [[String: Any]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        inner.editPlaylist(
            playlistId: playlistId,
            actions: actions,
            completion: completion
        )
    }

    func sendFeedback(
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        inner.sendFeedback(token: token, completion: completion)
    }

    private func deliver(
        stored: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            if stored {
                completion(.success(()))
            } else {
                completion(.failure(APIError.invalidResponse))
            }
        }
    }
}
