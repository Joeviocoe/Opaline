import UIKit

// MARK: - Starting, pre-rolling and moving the player

extension ShortsViewController {
    /// Uses the prefetched stream when the swipe beat the resolver to it.
    func startPlayback(of videoId: String) {
        logShortsTiming("playback start")
        // Already pre-rolled behind the current short: this is the path that
        // starts on the first frame instead of a poster.
        if playerView.advance(to: videoId, watchService: watchService) {
            return
        }
        if let entry = prefetcher.take(videoId: videoId) {
            playerView.attach(
                source: entry.source,
                playback: entry.playback,
                videoId: videoId,
                watchService: watchService
            )
            return
        }
        playerView.load(videoId: videoId, watchService: watchService)
    }

    /// Hands the next short to the player so it pre-rolls behind the current
    /// one. Called both on swipe and when a prefetch lands.
    func queueNext(after index: Int) {
        guard index == attachedIndex,
              let next = videos.dropFirst(index + 1).first,
              playerView.queuedVideoId != next.id,
              let entry = prefetcher.take(videoId: next.id) else {
            return
        }
        playerView.enqueue(
            source: entry.source,
            playback: entry.playback,
            videoId: next.id
        )
    }

    /// Resolves the next two shorts so the swipe has a stream waiting.
    func prefetchAround(_ index: Int) {
        // Three ahead, not two: a fast swipe used to outrun the resolver and
        // fall back to a full round trip.
        let next = Array(videos.dropFirst(index + 1).prefix(3))
        for video in next {
            prefetcher.prefetch(videoId: video.id)
        }
        // The channel name, avatar and like count all come off the watch
        // page. Fetched when the swipe lands it arrives seconds late — or
        // never, because the next swipe outruns it — so it is fetched ahead
        // alongside the stream.
        for offset in 0 ..< next.count {
            fetchMetadata(for: index + 1 + offset)
        }
        prefetcher.prune(keeping: Set(next.map { $0.id }))
    }

    func movePlayer(into container: UIView) {
        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor
            ),
            playerView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            ),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(
                equalTo: container.bottomAnchor
            )
        ])
    }
}
