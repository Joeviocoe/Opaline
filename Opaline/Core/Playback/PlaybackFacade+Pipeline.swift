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
        // Unconditional, and before the token check below: with no account
        // `fetchWatchtimeURLs` answers nil and nothing after this point runs.
        localWatchRecorder.start(videoId: videoId)
        apiClient.fetchWatchtimeURLs(
            videoId: videoId
        ) { [weak self] urls in
            guard let urls = urls,
                  let self = self
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
