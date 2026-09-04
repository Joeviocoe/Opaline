import Foundation

/// Orders the assembled feed, and remembers when each video was first seen
/// so that ordering is stable between refreshes.
///
/// **Why this is not just a sort by date.** The Videos tab dates a video
/// with `publishedTimeText` — "3 hours ago" — not the exact timestamp Atom
/// used to give. Everything published in the same hour therefore collapses
/// to one value, and Swift's `sort` is not a stable sort: with equal keys
/// the order is unspecified, so an identical rebuild could hand back a
/// different arrangement and the list would visibly reshuffle under the
/// reader for no reason.
///
/// So ties are broken, in order:
///
/// 1. **First seen, newest first.** A video that showed up on this refresh
///    and not the last one is almost certainly newer than one already on
///    screen in the same bucket. This is the only signal that recovers real
///    recency inside a bucket, and it costs nothing — it is local knowledge,
///    not another request.
/// 2. **Channel, then the channel's own order.** Within one channel the tab
///    is authoritative: it returns newest first, so its position is a true
///    ordering even when the dates read the same.
/// 3. **Video id.** Total and arbitrary, so the comparator can never fall
///    through to "unspecified".
///
/// The result is not exactly right — two channels publishing in the same
/// hour are ordered by when this device noticed them, not by the clock. It
/// is, however, deterministic and never goes backwards, which is the part a
/// reader would otherwise notice.
enum LocalFeedOrder {
    /// Video ids are ~11 chars; a few hundred is a few KB and covers far
    /// more than the 30-day window ever shows.
    private static let maxTracked = 600
    private static let key = UserDefaultsKeys.LocalLibrary.videoFirstSeen

    struct Entry {
        let video: Video
        /// Approximate publish time, from the relative text on the card.
        let date: Date
        /// Index of the channel in the subscription list — a fixed
        /// per-channel key, so the tie-break cannot depend on dictionary
        /// iteration order, which varies per process.
        let channelRank: Int
        /// Position within that channel's tab, which is newest-first.
        let positionInChannel: Int
    }

    /// Returns the entries, not just the videos: the caller still needs each
    /// one's date for the age window, and re-deriving it per video would be
    /// a lookup per element for something already in hand.
    static func sorted(_ entries: [Entry]) -> [Entry] {
        let seen = recordFirstSeen(entries.map { $0.video.id })
        return entries.sorted { lhs, rhs in
            isOrderedBefore(lhs, rhs, firstSeen: seen)
        }
    }

    private static func isOrderedBefore(
        _ lhs: Entry, _ rhs: Entry, firstSeen: [String: Double]
    ) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        let lhsSeen = firstSeen[lhs.video.id] ?? 0
        let rhsSeen = firstSeen[rhs.video.id] ?? 0
        if lhsSeen != rhsSeen {
            return lhsSeen > rhsSeen
        }
        if lhs.channelRank != rhs.channelRank {
            return lhs.channelRank < rhs.channelRank
        }
        if lhs.positionInChannel != rhs.positionInChannel {
            return lhs.positionInChannel < rhs.positionInChannel
        }
        return lhs.video.id < rhs.video.id
    }
}

// MARK: - First-seen ledger

extension LocalFeedOrder {
    /// Stamps any id we have not seen before with now, and returns the whole
    /// map. Ids keep their **original** stamp — that is the entire point, so
    /// a video does not get re-dated every time the feed rebuilds.
    static func recordFirstSeen(_ ids: [String]) -> [String: Double] {
        var seen = UserDefaults.standard
            .dictionary(forKey: key) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        var added = 0
        for id in ids where seen[id] == nil {
            seen[id] = now
            added += 1
        }
        guard added > 0 else {
            return seen
        }
        if seen.count > maxTracked {
            seen = prune(seen, keeping: Set(ids))
        }
        UserDefaults.standard.set(seen, forKey: key)
        AppLog.library(
            "feed order: \(added) newly seen, \(seen.count) tracked"
        )
        return seen
    }

    /// Keeps everything currently in the feed plus the most recently seen of
    /// the rest. Dropping an id is harmless — it just falls back to the
    /// channel/position tie-break — so this can be as blunt as it likes.
    private static func prune(
        _ seen: [String: Double], keeping current: Set<String>
    ) -> [String: Double] {
        let survivors = seen
            .filter { !current.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(max(0, maxTracked - current.count))
        var pruned: [String: Double] = [:]
        for id in current where seen[id] != nil {
            pruned[id] = seen[id]
        }
        for entry in survivors {
            pruned[entry.key] = entry.value
        }
        return pruned
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
