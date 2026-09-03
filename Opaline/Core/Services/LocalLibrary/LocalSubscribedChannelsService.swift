import Foundation

/// The subscribed-channels list, from the local store when there is no
/// account. Feeds the avatar bar and the channel filter, both of which
/// already speak `SubscribedChannel`.
final class LocalSubscribedChannelsService: SubscribedChannelsService {
    private let inner: SubscribedChannelsService
    private let store: LocalSubscriptionStore

    init(
        wrapping inner: SubscribedChannelsService,
        store: LocalSubscriptionStore = .shared
    ) {
        self.inner = inner
        self.store = store
    }

    func fetchSubscribedChannels(
        completion: @escaping (Result<[SubscribedChannel], Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.fetchSubscribedChannels(completion: completion)
            return
        }
        let channels = store.channels
        AppLog.library("local channels: \(channels.count)")
        DispatchQueue.main.async {
            completion(.success(channels))
        }
    }
}
