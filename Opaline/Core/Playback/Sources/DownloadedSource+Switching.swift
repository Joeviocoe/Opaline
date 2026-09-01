import Foundation

// MARK: - Switching between the saved file and the network

extension DownloadedSource {
    /// The saved copy costs nothing to go back to. A network rendition means
    /// loading the chain for real, which is why it only happens on an explicit
    /// pick and never as part of opening the video.
    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let videoId = videoId else {
            completion(.failure(DownloadError.missingFile))
            return
        }
        guard quality.id != Self.localQualityID else {
            setStreaming(false)
            playLocal(videoId: videoId, completion: completion)
            return
        }
        guard let network = network else {
            completion(.failure(DownloadError.missingFile))
            return
        }
        streamQuality(
            quality, from: network, resumeAt: resumeAt, completion: completion
        )
    }

    private func streamQuality(
        _ quality: VideoQuality,
        from network: VideoSource,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let videoId = videoId else {
            completion(.failure(DownloadError.missingFile))
            return
        }
        network.loadPlayback(videoId: videoId, cancellation: nil) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let prepared):
                self.setStreaming(true)
                // The chain may well have opened on the wanted rendition
                // already; asking it to switch to what it is playing would
                // cost a second round trip for nothing.
                guard network.currentQuality != quality else {
                    completion(.success(prepared))
                    return
                }
                network.selectQuality(
                    quality, resumeAt: resumeAt, completion: completion
                )
            }
        }
    }
}
