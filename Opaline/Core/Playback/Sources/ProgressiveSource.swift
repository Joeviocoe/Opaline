import AVFoundation
import Foundation

/// Progressive (single-file ~360p MP4) source — the low-fidelity fallback.
/// No quality selection.
final class ProgressiveSource: VideoSource {
    static let quality360 = VideoQuality(
        id: "progressive", label: "360p", height: 360, fps: nil
    )

    let kind: VideoSourceKind = .progressive
    let supportsQualitySelection = true
    let availableQualities: [VideoQuality] = [ProgressiveSource.quality360]
    let currentQuality: VideoQuality? = ProgressiveSource.quality360

    private let apiClient: WatchService
    private let client: DirectPlaybackClient = .androidVR

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
        let headers = client.streamHeaders(visitorData: info.visitorData)
        let asset = AVURLAsset(
            url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        completion(.success(
            PreparedPlayback(
                item: AVPlayerItem(asset: asset),
                captions: info.captionTracks,
                duration: info.duration
            )
        ))
    }
}
