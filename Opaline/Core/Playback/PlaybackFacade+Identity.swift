import Foundation

/// Everything one resolve pass needs to be judged and, if the visitor identity
/// it ran under turned out to be throttled, replayed under a fresh one.
struct ResolveAttempt {
    let videoId: String
    let apiClient: WatchService
    let cancellationToken: CancellationToken
    let kind: VideoSourceKind
    let startedAt: Date
    let identityGeneration: Int
}

// MARK: - Throttled-identity retries

extension PlaybackFacade {
    /// The resolve failed *and* the visitor identity was thrown out while it
    /// ran — so it failed because googlevideo throttles that identity, not
    /// because the video is unplayable. Draw again: only about a third of
    /// identities come up clean, and the probe in `HLSPlaybackBuilder` turns
    /// each draw into a verdict rather than a guess.
    ///
    /// Returns true when a retry was scheduled and the caller should stand down.
    func retryOnFreshIdentity(
        _ result: Swift.Result<PreparedPlayback, Error>,
        attempt: ResolveAttempt
    ) -> Bool {
        guard (try? result.get()) == nil,
              InnertubeSession.identityGeneration != attempt.identityGeneration,
              identityRedraws < Self.maxIdentityRedraws
        else {
            return false
        }
        identityRedraws += 1
        AppLog.player(
            "identity redraw \(identityRedraws)/\(Self.maxIdentityRedraws)"
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.identityRedrawDelay
        ) { [weak self] in
            guard !attempt.cancellationToken.isCancelled else {
                return
            }
            self?.start(
                videoId: attempt.videoId,
                apiClient: attempt.apiClient,
                cancellationToken: attempt.cancellationToken,
                kind: attempt.kind
            )
        }
        return true
    }
}
