import AVFoundation

final class SponsorBlockController {
    var segments: [SponsorBlockSegment] = []
    private var activeSegmentUUID: String?
    /// True while a skip's seek is still resolving.
    ///
    /// A zero-tolerance seek must decode from the preceding keyframe, and on a
    /// composition-backed item over a long GOP that takes longer than one tick
    /// of the periodic time observer. Without this guard the playhead reads
    /// back inside the segment before the seek lands, the skip re-fires, and
    /// the new seek cancels the one that would have escaped -- a livelock that
    /// looks exactly like playback hanging.
    private var isSeeking = false
    private weak var playerView: VideoPlayerView?

    func attach(to playerView: VideoPlayerView) {
        self.playerView = playerView
    }

    func reset() {
        segments = []
        activeSegmentUUID = nil
        isSeeking = false
    }

    func checkTime(_ time: Double) {
        guard SponsorBlockService.enabled, !segments.isEmpty
        else { return }
        // While a skip is seeking, the reported time is not where playback is
        // going to be. Acting on it clears the active segment and then skips
        // again, which is the livelock described above.
        guard !isSeeking else { return }

        let active = findActiveSegment(at: time)

        if let seg = active {
            if seg.uuid == activeSegmentUUID {
                return
            }
            activeSegmentUUID = seg.uuid
            handleSegment(seg)
        } else {
            if activeSegmentUUID != nil {
                activeSegmentUUID = nil
                playerView?.hideSkipButton()
            }
        }
    }

    private func findActiveSegment(at time: Double) -> SponsorBlockSegment? {
        segments.first { seg in
            guard seg.actionType == "skip" || seg.actionType == "poi"
            else { return false }
            let behavior = SponsorBlockService.skipBehavior(for: seg.category)
            guard behavior != .disabled
            else { return false }
            return time >= seg.startTime && time < seg.endTime
        }
    }

    private func handleSegment(_ seg: SponsorBlockSegment) {
        let behavior = SponsorBlockService.skipBehavior(for: seg.category)
        switch behavior {
        case .autoSkip:
            guard let player = playerView?.player
            else { return }
            let target = CMTime(
                seconds: seg.endTime, preferredTimescale: 600
            )
            isSeeking = true
            let startedAt = Date()
            player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] finished in
                self?.isSeeking = false
                let ms = Int(Date().timeIntervalSince(startedAt) * 1_000)
                AppLog.sponsorBlock(
                    "skip seek \(finished ? "completed" : "interrupted")"
                        + " to \(seg.endTime) in \(ms)ms"
                )
            }
            AppLog.sponsorBlock(
                "auto-skipped \(seg.category.displayName) "
                    + "[\(seg.startTime)–\(seg.endTime)]"
            )
        case .showButton:
            playerView?.showSkipButton(
                categoryName: seg.category.displayName
            )
        case .disabled:
            break
        }
    }

    func skipCurrentSegment() {
        guard let uuid = activeSegmentUUID,
              let seg  = segments.first(where: { $0.uuid == uuid }),
              let player = playerView?.player
        else { return }
        let target = CMTime(seconds: seg.endTime, preferredTimescale: 600)
        isSeeking = true
        let startedAt = Date()
        player.seek(
            to: target, toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] finished in
            self?.isSeeking = false
            let ms = Int(Date().timeIntervalSince(startedAt) * 1_000)
            AppLog.sponsorBlock(
                "manual skip seek \(finished ? "completed" : "interrupted")"
                    + " to \(seg.endTime) in \(ms)ms"
            )
        }
        activeSegmentUUID = nil
        playerView?.hideSkipButton()
        AppLog.sponsorBlock(
            "user skipped \(seg.category.displayName) "
                + "[\(seg.startTime)–\(seg.endTime)]"
        )
    }
}
