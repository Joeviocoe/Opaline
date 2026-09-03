import Foundation

/// Channels subscribed to on this device, with no account.
///
/// Main-thread API, lazily loaded. One write per tap rather than a debounce:
/// a subscribe is a deliberate, infrequent user action, and the cost of
/// losing one to a crash is much higher than the cost of the write.
final class LocalSubscriptionStore {
    static let shared = LocalSubscriptionStore()
    static let didChangeNotification = Notification.Name(
        "LocalSubscriptionStoreDidChange"
    )

    /// A deliberate choice each, so the cap refuses rather than evicting —
    /// silently dropping the oldest subscription is not a thing to do to
    /// somebody's library.
    private static let maxChannels = 1_000
    private static let fileName = "subscriptions.json"

    private var loaded = false
    private var storage: [LocalSubscription] = []
    private var index: Set<String> = []
    /// Set when the file on disk could not be read. While true nothing is
    /// written back, because whatever is there is data this build does not
    /// understand — not an empty library.
    private var isReadOnly = false

    private init() {}

    var subscriptions: [LocalSubscription] {
        loadIfNeeded()
        return storage
    }

    /// Newest first, matching how the avatar bar wants them.
    var channels: [SubscribedChannel] {
        subscriptions
            .sorted { $0.subscribedAt > $1.subscribedAt }
            .map { $0.channel }
    }

    var count: Int {
        subscriptions.count
    }

    func isSubscribed(channelId: String) -> Bool {
        loadIfNeeded()
        return index.contains(channelId)
    }

    @discardableResult
    func subscribe(
        channelId: String,
        title: String,
        avatarURL: String?
    ) -> Bool {
        loadIfNeeded()
        guard !index.contains(channelId) else {
            return true
        }
        guard storage.count < LocalSubscriptionStore.maxChannels else {
            AppLog.library(
                "subscribe \(channelId): REFUSED, at cap"
                    + " \(LocalSubscriptionStore.maxChannels)"
            )
            return false
        }
        storage.append(
            LocalSubscription(
                channelId: channelId,
                title: title,
                avatarURL: avatarURL
            )
        )
        index.insert(channelId)
        AppLog.library(
            "subscribe \(channelId) '\(title)'"
                + " avatar=\(avatarURL != nil) total=\(storage.count)"
        )
        persistAndNotify()
        return true
    }

    @discardableResult
    func unsubscribe(channelId: String) -> Bool {
        loadIfNeeded()
        guard let position = storage.firstIndex(
            where: { $0.channelId == channelId }
        ) else {
            return false
        }
        storage.remove(at: position)
        index.remove(channelId)
        AppLog.library(
            "unsubscribe \(channelId) total=\(storage.count)"
        )
        persistAndNotify()
        return true
    }

    func clear() {
        loadIfNeeded()
        guard !storage.isEmpty else {
            return
        }
        storage = []
        index = []
        AppLog.library("subscriptions cleared")
        persistAndNotify()
    }

    /// JSON for the Settings export — the stored shape as-is, so an export
    /// and the file on disk never drift apart.
    func exportData() -> Data? {
        loadIfNeeded()
        return try? JSONEncoder().encode(storage)
    }
}

// MARK: - Persistence

private extension LocalSubscriptionStore {
    func loadIfNeeded() {
        guard !loaded else {
            return
        }
        loaded = true
        let result = LocalLibraryFile.load(
            LocalSubscription.self,
            fileName: LocalSubscriptionStore.fileName
        )
        switch result {
        case .empty:
            storage = []
        case .loaded(let items):
            storage = items
        case .unreadable:
            // Keep whatever is on disk: an unreadable file is not an empty
            // library, and this is the user's only copy.
            storage = []
            isReadOnly = true
        }
        index = Set(storage.map { $0.channelId })
    }

    func persistAndNotify() {
        guard !isReadOnly else {
            AppLog.library("subscriptions: write skipped, file unreadable")
            return
        }
        LocalLibraryFile.save(
            storage, fileName: LocalSubscriptionStore.fileName
        )
        NotificationCenter.default.post(
            name: LocalSubscriptionStore.didChangeNotification,
            object: nil
        )
    }
}
