import AVFoundation
import UIKit

enum PlaybackBufferPolicy {
    static let defaultForwardBufferDuration: TimeInterval = 20.0
    static let backgroundBufferDuration: TimeInterval = 30.0

    static func configure(
        item: AVPlayerItem,
        forwardBufferDuration: TimeInterval = defaultForwardBufferDuration
    ) {
        item.preferredForwardBufferDuration = forwardBufferDuration
    }

    static func configure(
        player: AVPlayer,
        waitsToMinimizeStalling: Bool = true
    ) {
        player.automaticallyWaitsToMinimizeStalling =
            waitsToMinimizeStalling
        // Keeps audio going in the background without detaching the player
        // from its layer — the detach is what breaks PiP (#28). Older iOS
        // has no such policy and falls back to detaching.
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
    }
}

/// Drives source-based playback: picks a `VideoSource` via the factory, loads
/// it, and hands the prepared item to the `PlaybackContext` (player shell).
final class PlaybackFacade {
    /// Recoveries closer together than this are one failing streak; a lone
    /// one hours later (URL expiry) starts the ladder over.
    private static let recoveryStreakWindow: TimeInterval = 60

    weak var context: PlaybackContext?
    /// The active source — owns stream resolution and quality selection.
    var activeVideoSource: VideoSource?
    let watchtimeTracker = WatchtimeTracker()
    var currentVideoId: String?
    weak var currentApiClient: WatchService?
    /// Video that already burned its one silent bot-check retry.
    var botCheckRetriedVideoId: String?
    /// Consecutive mid-playback recoveries, for the escalation ladder.
    var recoveryAttempts = 0
    /// When the last recovery started — an isolated one (URL expiry hours
    /// later) must not count against the ladder.
    var lastRecoveryAt: Date?
}

// MARK: - Public API

extension PlaybackFacade {
    func start(
        videoId: String,
        apiClient: WatchService,
        cancellationToken: CancellationToken,
        kind: VideoSourceKind = PlaybackSource.selected.sourceKind,
        statusKey: String = "player.status.resolving"
    ) {
        currentVideoId = videoId
        currentApiClient = apiClient
        let source = DefaultVideoSourceFactory(apiClient: apiClient)
            .make(kind: kind)
        activeVideoSource = source
        context?.updateStatusLabel(statusKey.localized)
        let t0 = Date()
        source.loadPlayback(
            videoId: videoId,
            cancellation: cancellationToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                let ms = Int(Date().timeIntervalSince(t0) * 1_000)
                let verdict = (try? result.get()) == nil ? "failed" : "ok"
                AppLog.player("resolve \(verdict) on \(kind) in \(ms)ms")
                guard let self,
                      !cancellationToken.isCancelled else {
                    return
                }
                self.handlePrepared(result, cancellation: cancellationToken)
            }
        }
    }

    /// Restarts playback after a mid-playback failure (segment 403, fatal
    /// stall). The source can't see these itself — its manifest loaded fine,
    /// so its own load-time fallback never fires. Escalate instead: refresh
    /// the same source once (that fixes genuine URL expiry), then rebuild on
    /// a different client, then stop. Returns false when the budget is spent
    /// — the shell shows the error rather than hammering the API forever.
    func recover(cancellationToken: CancellationToken) -> Bool {
        guard let videoId = currentVideoId,
              let apiClient = currentApiClient else {
            return false
        }
        if let last = lastRecoveryAt,
           Date().timeIntervalSince(last) > Self.recoveryStreakWindow {
            recoveryAttempts = 0
        }
        lastRecoveryAt = Date()
        recoveryAttempts += 1
        let selected = PlaybackSource.selected.sourceKind
        let kind: VideoSourceKind
        switch recoveryAttempts {
        case 1:
            kind = selected
        case 2:
            kind = escalated(from: selected)
        default:
            AppLog.player("recovery: retries spent, giving up")
            return false
        }
        AppLog.player("recovery attempt \(recoveryAttempts) on \(kind)")
        start(
            videoId: videoId,
            apiClient: apiClient,
            cancellationToken: cancellationToken,
            kind: kind,
            statusKey: "player.status.refreshing"
        )
        return true
    }

    /// Whatever the failing stream came from, hand the next attempt to a
    /// different client — the same one would serve the same dead URLs.
    private func escalated(
        from kind: VideoSourceKind
    ) -> VideoSourceKind {
        switch kind {
        case .auto, .androidVR, .progressive:
            return .mwebPot
        case .mwebPot:
            return .androidVR
        }
    }

    private func handlePrepared(
        _ result: Result<PreparedPlayback, Error>,
        cancellation: CancellationToken
    ) {
        switch result {
        case .success(let prepared):
            let kind = activeVideoSource?.kind
            let count = activeVideoSource?.availableQualities.count ?? 0
            AppLog.player(
                "source \(String(describing: kind)) playing, \(count) qualities"
            )
            context?.attachPrepared(prepared, resumeAt: nil)
            fetchWatchtimeAndTrack()
        case .failure(let error):
            AppLog.player("source playback failed: \(error)")
            guard isBotCheck(error) else {
                context?.showPlaybackError("player.error.playback".localized)
                return
            }
            if !retryAfterBotCheck(cancellation: cancellation) {
                context?.showPlaybackError("player.error.botCheck".localized)
            }
        }
    }

    private func isBotCheck(_ error: Error) -> Bool {
        guard let apiError = error as? APIError,
              case .botCheck = apiError else {
            return false
        }
        return true
    }

    /// Parsing the bot check already dropped the flagged visitor identity, so
    /// one silent reload — fresh identity, whole source chain again — usually
    /// just plays. Only ever retried once per video; then the user sees why.
    private func retryAfterBotCheck(
        cancellation: CancellationToken
    ) -> Bool {
        guard let videoId = currentVideoId,
              let apiClient = currentApiClient,
              botCheckRetriedVideoId != videoId,
              !cancellation.isCancelled else {
            return false
        }
        botCheckRetriedVideoId = videoId
        AppLog.player("bot check — retrying with a fresh visitor identity")
        // The label stays up for the whole retry — `start` would immediately
        // overwrite anything set here with its own status.
        start(
            videoId: videoId,
            apiClient: apiClient,
            cancellationToken: cancellation,
            statusKey: "player.status.botCheckRetry"
        )
        return true
    }

    func reset() {
        activeVideoSource = nil
        watchtimeTracker.stop()
        currentVideoId = nil
        currentApiClient = nil
        botCheckRetriedVideoId = nil
        recoveryAttempts = 0
        lastRecoveryAt = nil
    }
}
