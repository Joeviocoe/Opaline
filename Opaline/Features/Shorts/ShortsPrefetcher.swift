import AVFoundation
import Foundation

/// Resolves the next shorts ahead of the swipe. Stream resolution is what
/// the "Resolving stream…" wait actually is — the API round trip plus the
/// manifest build — so resolving early removes almost all of it.
///
/// Resolve only: an idle second AVPlayer to pre-buffer the item is not worth
/// it, because handing that item to the real player crashes. AVFoundation
/// detaches an item from its old player asynchronously, so the attach on the
/// main thread lands while the item still belongs to the warm-up player and
/// AVPlayerItem._attachToPlayer throws. Verified on device.
final class ShortsPrefetcher {
    /// Resolved and ready to attach, keyed by videoId.
    private var ready: [String: (source: VideoSource, playback: PreparedPlayback)] = [:]
    /// In flight, so a re-entrant swipe does not resolve the same short twice.
    private var inFlight: Set<String> = []
    private let watchService: WatchService

    init(watchService: WatchService) {
        self.watchService = watchService
    }

    /// Resolves `videoId` unless it is already ready or being resolved.
    func prefetch(videoId: String) {
        guard ready[videoId] == nil,
              inFlight.insert(videoId).inserted else {
            return
        }
        let source = DefaultVideoSourceFactory(apiClient: watchService)
            .make(kind: PlaybackSource.selected.sourceKind)
        source.loadPlayback(
            videoId: videoId, cancellation: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.store(result, source: source, videoId: videoId)
            }
        }
    }

    /// Hands over a resolved short, giving up ownership — the caller retains
    /// the source for as long as its item plays.
    func take(videoId: String) -> (source: VideoSource, playback: PreparedPlayback)? {
        ready.removeValue(forKey: videoId)
    }

    /// Drops everything outside `keep` — swiping past a short makes its
    /// resolved stream dead weight (and its URLs expire anyway).
    func prune(keeping keep: Set<String>) {
        for id in ready.keys where !keep.contains(id) {
            ready.removeValue(forKey: id)
        }
    }

    private func store(
        _ result: Result<PreparedPlayback, Error>,
        source: VideoSource,
        videoId: String
    ) {
        inFlight.remove(videoId)
        guard case .success(let playback) = result else {
            AppLog.player("shorts prefetch failed for \(videoId)")
            return
        }
        ready[videoId] = (source, playback)
    }
}
