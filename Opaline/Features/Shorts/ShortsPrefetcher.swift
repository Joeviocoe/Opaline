import AVFoundation
import Foundation

/// Resolves the next shorts ahead of the swipe. Stream resolution is what
/// the "Resolving stream…" wait actually is — the API round trip plus the
/// manifest build — so resolving early removes almost all of it.
///
/// Depth is deliberately small: one extra idle AVPlayer warms the immediate
/// next short's buffer, and only resolved results are held beyond that.
/// A7-era devices cannot afford a row of buffering players.
final class ShortsPrefetcher {
    /// Resolved and ready to attach, keyed by videoId.
    private var ready: [String: (source: VideoSource, playback: PreparedPlayback)] = [:]
    /// In flight, so a re-entrant swipe does not resolve the same short twice.
    private var inFlight: Set<String> = []
    /// Holds the next short's item so it fills its buffer before the swipe.
    private let warmup = AVPlayer()
    private var warmedVideoId: String?
    private let watchService: WatchService

    init(watchService: WatchService) {
        self.watchService = watchService
        warmup.volume = 0
        PlaybackBufferPolicy.configure(player: warmup)
    }

    /// Resolves `videoId` unless it is already ready or being resolved.
    /// `warm` additionally parks the item in the idle player to buffer it.
    func prefetch(videoId: String, warm: Bool) {
        if ready[videoId] != nil {
            if warm {
                startWarming(videoId: videoId)
            }
            return
        }
        guard inFlight.insert(videoId).inserted else {
            return
        }
        let source = DefaultVideoSourceFactory(apiClient: watchService)
            .make(kind: PlaybackSource.selected.sourceKind)
        source.loadPlayback(
            videoId: videoId, cancellation: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.store(result, source: source, videoId: videoId, warm: warm)
            }
        }
    }

    /// Hands over a resolved short, giving up ownership — the caller retains
    /// the source for as long as its item plays.
    func take(videoId: String) -> (source: VideoSource, playback: PreparedPlayback)? {
        if warmedVideoId == videoId {
            warmup.replaceCurrentItem(with: nil)
            warmedVideoId = nil
        }
        return ready.removeValue(forKey: videoId)
    }

    /// Drops everything outside `keep` — swiping past a short makes its
    /// resolved stream dead weight (and its URLs expire anyway).
    func prune(keeping keep: Set<String>) {
        for id in ready.keys where !keep.contains(id) {
            ready.removeValue(forKey: id)
        }
        if let warmed = warmedVideoId, !keep.contains(warmed) {
            warmup.replaceCurrentItem(with: nil)
            warmedVideoId = nil
        }
    }

    private func store(
        _ result: Result<PreparedPlayback, Error>,
        source: VideoSource,
        videoId: String,
        warm: Bool
    ) {
        inFlight.remove(videoId)
        guard case .success(let playback) = result else {
            AppLog.player("shorts prefetch failed for \(videoId)")
            return
        }
        ready[videoId] = (source, playback)
        if warm {
            startWarming(videoId: videoId)
        }
    }

    private func startWarming(videoId: String) {
        guard warmedVideoId != videoId,
              let entry = ready[videoId] else {
            return
        }
        warmedVideoId = videoId
        PlaybackBufferPolicy.configure(item: entry.playback.item)
        // Paused, but attaching is what makes the item start filling.
        warmup.replaceCurrentItem(with: entry.playback.item)
        warmup.pause()
    }
}
