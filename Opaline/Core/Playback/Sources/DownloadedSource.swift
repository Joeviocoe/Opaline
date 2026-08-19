import AVFoundation
import Foundation

/// Plays a video that is already on disk.
///
/// No local HTTP server stands in front of the file: `AVPlayer` opens a
/// `file://` URL natively, seeking is free and there is nothing to keep alive
/// while the app is backgrounded. Everything above the player shell talks to
/// `VideoSource`, so an offline video is not a special case anywhere else.
///
/// Subtitles come from what was saved beside the file: the local item carries
/// no caption tracks of its own, and nothing else on this path asks the
/// network for them. Only the languages chosen at download time are listed,
/// online as well as offline.
/// ponytail: saved languages only; ask the network for the rest if someone
/// misses a language while online.
///
/// The saved file always plays first, with no network in the way. What the
/// network could serve is probed behind it: online, the quality menu offers
/// the full ladder next to the saved copy; offline the probe simply fails and
/// only the saved copy is listed.
final class DownloadedSource: VideoSource {
    static let localQualityID = "downloaded"

    var name: String {
        isStreaming ? (network?.name ?? "downloaded") : "downloaded"
    }

    let supportsQualitySelection = true

    var availableQualities: [VideoQuality] {
        localQuality.map { [$0] + networkQualities } ?? networkQualities
    }

    var currentQuality: VideoQuality? {
        isStreaming ? network?.currentQuality : localQuality
    }

    var currentCodecs: String? { isStreaming ? network?.currentCodecs : nil }

    let network: VideoSource?
    private var localQuality: VideoQuality?
    private var networkQualities: [VideoQuality] = []
    private(set) var isStreaming = false
    private(set) var videoId: String?

    init(network: VideoSource? = nil) {
        self.network = network
    }

    /// Read off the file itself — nothing about the download is stored
    /// alongside it yet.
    private static func quality(of asset: AVURLAsset) -> VideoQuality {
        let size = asset.tracks(withMediaType: .video).first?.naturalSize
        let height = Int(abs(size?.height ?? 0))
        return VideoQuality(
            id: localQualityID,
            label: height > 0
                ? "downloads.quality.saved".localized(with: "\(height)p")
                : "downloads.quality.savedPlain".localized,
            height: height > 0 ? height : nil,
            fps: nil
        )
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        self.videoId = videoId
        isStreaming = false
        playLocalFile(videoId: videoId, completion: completion)
        probeNetworkQualities(videoId: videoId)
    }

    func releaseResources() {
        network?.releaseResources()
    }

    func setStreaming(_ streaming: Bool) {
        isStreaming = streaming
    }

    func playLocal(
        videoId: String,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        playLocalFile(videoId: videoId, completion: completion)
    }

    private func playLocalFile(
        videoId: String,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let url = DownloadStore.videoFile(for: videoId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(.failure(DownloadError.missingFile))
            return
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        localQuality = Self.quality(of: asset)
        AppLog.player("downloaded file \(videoId): \(Int(seconds))s")
        completion(.success(PreparedPlayback(
            item: AVPlayerItem(asset: asset),
            captions: DownloadStore.captionTracks(for: videoId) ?? [],
            duration: seconds.isFinite ? seconds : nil
        )))
    }

    /// Runs behind playback that has already started, so a slow or absent
    /// network costs the saved file nothing.
    private func probeNetworkQualities(videoId: String) {
        network?.probeQualities(videoId: videoId) { [weak self] qualities in
            self?.networkQualities = qualities
            AppLog.player("downloaded: \(qualities.count) network qualities")
        }
    }
}
