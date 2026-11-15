import Foundation

extension SubscriptionsViewController {
    /// The date a video sorts by. Exact when one was seeded (shorts arrive
    /// with a real timestamp), otherwise approximated from the card's
    /// relative text against `now`.
    ///
    /// Only exact dates are cached. An approximation is `now - offset`, so
    /// caching one and comparing it against another computed on a later
    /// refresh orders two "3 hours ago" videos by when this screen first
    /// saw them, not by anything on the cards. The offset itself is cached
    /// per text inside `ContentKeywords`, so recomputing here is cheap.
    func sortDate(for video: Video, now: Date) -> Date {
        if let exact = sortDatesByVideoId[video.id] {
            return exact
        }
        return video.publishedAt.flatMap {
            VideoFormatters.approximateDate(fromRelative: $0, now: now)
        } ?? .distantPast
    }

    func mergeSortedVideos(
        _ lhs: [Video],
        _ rhs: [Video]
    ) -> [Video] {
        guard !lhs.isEmpty else {
            return rhs
        }
        guard !rhs.isEmpty else {
            return lhs
        }

        let now = Date()
        var merged: [Video] = []
        merged.reserveCapacity(lhs.count + rhs.count)
        var lhsIndex = 0
        var rhsIndex = 0

        while lhsIndex < lhs.count, rhsIndex < rhs.count {
            let lhsVideo = lhs[lhsIndex]
            let rhsVideo = rhs[rhsIndex]
            if sortDate(for: lhsVideo, now: now)
                >= sortDate(for: rhsVideo, now: now) {
                merged.append(lhsVideo)
                lhsIndex += 1
            } else {
                merged.append(rhsVideo)
                rhsIndex += 1
            }
        }

        if lhsIndex < lhs.count {
            merged.append(contentsOf: lhs[lhsIndex...])
        }
        if rhsIndex < rhs.count {
            merged.append(contentsOf: rhs[rhsIndex...])
        }
        return merged
    }
}
