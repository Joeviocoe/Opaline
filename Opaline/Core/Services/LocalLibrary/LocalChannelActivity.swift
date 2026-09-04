import Foundation

/// When each subscribed channel last published, so the avatar bar and the
/// All-channels list can lead with whoever posted most recently.
///
/// Derived data, deliberately kept out of `LocalSubscription`. The
/// subscriptions file is the user's only copy of their library and is
/// written once per deliberate tap; this is rewritten by every feed refresh,
/// and a refresh has no business touching that file. Losing this map costs
/// nothing — the order falls back to subscription recency until the next
/// fetch fills it in again.
///
/// `UserDefaults` for the same reason it is not a file: one `Double` per
/// channel against a 1000-channel cap is a few KB, it is already resident at
/// launch, and being readable **synchronously during the first paint** is
/// the whole point. A map that arrived after the bar was laid out would just
/// reorder it under the user, which is the flicker this exists to avoid.
enum LocalChannelActivity {
    private static let key = UserDefaultsKeys.LocalLibrary.channelActivity

    /// channelId -> seconds since 1970 of that channel's newest upload.
    static var all: [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
            ?? [:]
    }

    /// Merges rather than replaces: a channel whose fetch failed this round
    /// keeps the date it already had, so one bad request does not drop it to
    /// the bottom of the bar.
    static func record(_ dates: [String: Date]) {
        guard !dates.isEmpty else {
            return
        }
        var merged = all
        for (channelId, date) in dates {
            merged[channelId] = date.timeIntervalSince1970
        }
        UserDefaults.standard.set(merged, forKey: key)
        AppLog.library(
            "channel activity: \(dates.count) dated,"
                + " \(merged.count) known"
        )
    }

    /// Dropped on unsubscribe, so the map cannot outlive the library it
    /// describes and grow without bound across a lot of churn.
    static func forget(channelId: String) {
        var merged = all
        guard merged.removeValue(forKey: channelId) != nil else {
            return
        }
        UserDefaults.standard.set(merged, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Orders two subscriptions for display: most recent upload first, which
    /// is left-to-right in the avatar bar and top-down in the All list.
    ///
    /// A channel with no date sorts to the end. That one rule covers all
    /// three ways a date can be missing — just subscribed and nothing
    /// fetched yet, a fetch that failed, or an id the feed cannot read — and
    /// puts a brand-new subscription at the top of that tail rather than
    /// losing it in the middle of the list.
    ///
    /// **Ties must be broken explicitly.** Dates now come from the relative
    /// text on a card ("3 hours ago"), so every channel that posted within
    /// the same hour — or the same week, further back — shares one value.
    /// Swift's sort is not stable, so without a tie-break the bar would deal
    /// those channels out in a different order on each rebuild and appear to
    /// shuffle itself for no reason. `subscribedAt` then `channelId` gives a
    /// total order, so identical input always renders identically.
    static func isOrderedBefore(
        _ lhs: LocalSubscription,
        _ rhs: LocalSubscription,
        activity: [String: Double]
    ) -> Bool {
        switch (activity[lhs.channelId], activity[rhs.channelId]) {
        case let (left?, right?):
            if left != right {
                return left > right
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        if lhs.subscribedAt != rhs.subscribedAt {
            return lhs.subscribedAt > rhs.subscribedAt
        }
        return lhs.channelId < rhs.channelId
    }
}
