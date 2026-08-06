import AVFoundation

extension PlaybackFacade {
    /// Starts YouTube watch-history tracking for the active video (cross-cutting;
    /// runs for every source once playback is attached).
    func fetchWatchtimeAndTrack() {
        guard let videoId = currentVideoId,
              let apiClient = currentApiClient
        else {
            return
        }
        apiClient.fetchWatchtimeURLs(
            videoId: videoId
        ) { [weak self] urls in
            guard let urls,
                  let self
            else {
                return
            }
            self.watchtimeTracker.start(
                videoId: videoId,
                urls: urls
            )
        }
    }
}
