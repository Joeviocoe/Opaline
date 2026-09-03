import Foundation

/// Remembers what a channel is called and what it looks like, so a
/// subscription made with no account can be stored with a real name and
/// avatar instead of a bare id.
///
/// This exists because `subscribeToChannel` carries only a channel id, and
/// changing that signature would be a guaranteed cherry-pick conflict with
/// upstream. So identity travels alongside the call instead: whoever has it
/// at the tap (`SubscribeAction`) notes it here, and `LocalEngagementService`
/// reads it back when it writes the store.
///
/// Memory only, and deliberately so — it is a hint, not a source of truth,
/// and `AppCache`'s own channel-info cache is the fallback.
final class LocalChannelIdentity {
    static let shared = LocalChannelIdentity()

    private static let maxEntries = 200

    private let lock = NSLock()
    private var known: [String: SubscribedChannel] = [:]
    /// Least-recently-noted first, so eviction drops the coldest entry.
    private var order: [String] = []

    private init() {}

    func remember(_ channel: SubscribedChannel) {
        let channelId = channel.id
        guard !channelId.isEmpty else {
            return
        }
        lock.lock()
        known[channelId] = channel
        order.removeAll { $0 == channelId }
        order.append(channelId)
        if order.count > LocalChannelIdentity.maxEntries {
            let evicted = order.removeFirst()
            known[evicted] = nil
        }
        lock.unlock()
    }

    /// The remembered identity, the cached channel info, or nothing —
    /// in that order. A caller that gets nothing back still subscribes; the
    /// row simply shows a placeholder until something enriches it.
    func identity(for channelId: String) -> (
        title: String, avatarURL: String?, source: String
    ) {
        lock.lock()
        let remembered = known[channelId]
        lock.unlock()
        if let remembered = remembered {
            return (remembered.title, remembered.avatarURL, "noted")
        }
        if let cached = AppCache.shared.cachedChannelInfo(
            channelId: channelId
        ) {
            return (cached.title, cached.avatarURL, "cache")
        }
        return ("", nil, "none")
    }
}
