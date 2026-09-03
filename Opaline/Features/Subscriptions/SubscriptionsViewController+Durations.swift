import UIKit

// MARK: - Filling in durations the Atom feed cannot supply
//
// Deliberately driven by scrolling *stopping*, not by `willDisplay`: rows
// that fly past during a flick cost nothing, and on an A5X that is the
// difference between a smooth list and one that stutters while it fetches
// browse payloads for cells the reader never looked at. It is the same
// discipline the thumbnail loader already follows.

extension SubscriptionsViewController {
    func enrichVisibleDurations() {
        guard LocalLibrary.isActive else {
            // The account feed already carries durations; there is nothing
            // to fill in and no reason to spend a request.
            AppLog.subs("durations: skipped, signed in")
            return
        }
        let visible = tableView.indexPathsForVisibleRows?.count ?? -1
        let channels = visibleChannelsNeedingDurations()
        guard !channels.isEmpty else {
            // Every early return here is logged deliberately. The first cut
            // of this had silent guards, nothing ran, and the log gave no
            // way to tell which one ate it — a whole build wasted guessing.
            AppLog.subs(
                "durations: nothing to do — visibleRows=\(visible)"
                    + " rows=\(rows.count) videos=\(videos.count)"
            )
            return
        }
        AppLog.subs(
            "durations: asking \(channels.count) channel(s),"
                + " visibleRows=\(visible)"
        )
        for channelId in channels {
            ChannelDurationStore.shared.prefetch(
                channelId: channelId
            ) { [weak self] in
                self?.applyDurationsToVisibleRows()
            }
        }
    }

    /// Channels of the rows actually on screen whose videos still have no
    /// duration — deduplicated, because one fetch covers every video that
    /// channel contributed.
    private func visibleChannelsNeedingDurations() -> Set<String> {
        guard let paths = tableView.indexPathsForVisibleRows else {
            return []
        }
        var channels: Set<String> = []
        var notVideo = 0
        var haveDuration = 0
        var noChannelId = 0
        for path in paths {
            guard path.row < rows.count else {
                continue
            }
            guard case let .video(video) = rows[path.row] else {
                notVideo += 1
                continue
            }
            guard video.duration?.isEmpty != false else {
                haveDuration += 1
                continue
            }
            guard let channelId = video.channelId, !channelId.isEmpty else {
                noChannelId += 1
                continue
            }
            channels.insert(channelId)
        }
        // Which of the three reasons a visible row was passed over — the
        // difference between "already has durations", "these are not video
        // rows" and "the feed carries no channel ids", each of which needs a
        // completely different fix.
        if channels.isEmpty {
            AppLog.subs(
                "durations: rejected \(paths.count) visible —"
                    + " notVideo=\(notVideo) haveDuration=\(haveDuration)"
                    + " noChannelId=\(noChannelId)"
            )
        }
        return channels
    }

    /// Writes whatever the store now knows into `videos`, in one assignment,
    /// then re-measures only the rows that gained a line.
    ///
    /// One assignment matters: `videos` has a `didSet` that rebuilds `rows`,
    /// so mutating it per element would rebuild the whole list once per
    /// video and invalidate the indices mid-loop. Build the new array, set
    /// it once, let `didSet` regenerate `rows` — which is also why nothing
    /// here patches `rows` directly.
    func applyDurationsToVisibleRows() {
        var updated = videos
        var changedVideoIndices: [Int] = []
        for (index, video) in updated.enumerated() {
            guard video.duration?.isEmpty != false,
                  let channelId = video.channelId,
                  let map = ChannelDurationStore.shared.durations(
                      forChannel: channelId
                  ),
                  let duration = map[video.id]
            else {
                continue
            }
            updated[index].duration = duration
            changedVideoIndices.append(index)
        }
        guard !changedVideoIndices.isEmpty else {
            AppLog.subs(
                "durations: store answered but matched no video"
                    + " (\(videos.count) in feed)"
            )
            return
        }
        videos = updated
        AppLog.subs("durations: filled \(changedVideoIndices.count) rows")
        reloadRowsForVideos(at: changedVideoIndices)
    }

    /// A shorts shelf, when present, occupies row 0 — so a video's index in
    /// `videos` is not its row. Reloading rather than touching the label
    /// because the row is now one line taller and has to be re-measured.
    private func reloadRowsForVideos(at videoIndices: [Int]) {
        let offset = shortsShelf.isEmpty ? 0 : 1
        let visible = Set(tableView.indexPathsForVisibleRows ?? [])
        let paths = videoIndices
            .map { IndexPath(row: $0 + offset, section: 0) }
            .filter { visible.contains($0) && $0.row < rows.count }
        guard !paths.isEmpty else {
            return
        }
        // No animation: this lands under the reader's eyes, and a fade on
        // rows changing height is exactly the churn worth avoiding here.
        UIView.performWithoutAnimation {
            tableView.reloadRows(at: paths, with: .none)
        }
    }
}
