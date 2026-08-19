import AVFoundation
import Foundation

/// Progressive (single-file ~360p MP4) source — the low-fidelity fallback.
/// No quality selection.
final class ProgressiveSource: VideoSource {
    static let quality360 = VideoQuality(
        id: "progressive", label: "360p", height: 360, fps: nil
    )

    let name = "progressive"
    let supportsQualitySelection = true
    let availableQualities: [VideoQuality] = [ProgressiveSource.quality360]
    let currentQuality: VideoQuality? = ProgressiveSource.quality360

    private let apiClient: WatchService
    private let client: PlaybackClient = AndroidClient()

    init(apiClient: WatchService) {
        self.apiClient = apiClient
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        apiClient.fetchDirectPlayback(
            videoId: videoId,
            client: client,
            poToken: nil,
            cancellationToken: cancellation
        ) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let info):
                self?.play(info, completion: completion)
            }
        }
    }

    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        completion(.failure(
            NSError(domain: "ProgressiveSource", code: 0)
        ))
    }

    private func play(
        _ info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if info.progressiveURL == nil, let hls = info.hlsManifestURL {
            completion(.success(item(for: hls, info: info)))
            return
        }
        guard let url = info.progressiveURL else {
            completion(.failure(
                NSError(
                    domain: "ProgressiveSource",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No progressive stream"
                    ]
                )
            ))
            return
        }
        completion(.success(item(for: url, info: info)))
    }

    private func item(for url: URL, info: DirectPlaybackInfo) -> PreparedPlayback {
        let headers = client.streamHeaders(visitorData: info.visitorData)
        let asset = AVURLAsset(
            url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return PreparedPlayback(
            item: AVPlayerItem(asset: asset),
            captions: info.captionTracks,
            duration: info.duration
        )
    }
}
