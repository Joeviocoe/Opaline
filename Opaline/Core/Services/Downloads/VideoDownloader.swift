import Foundation

/// One downloadable rendition, as offered by the quality prompt.
struct DownloadOption {
    let label: String
    let height: Int
    let video: DashFormatInfo
    let audio: DashFormatInfo

    var bytes: Int64 { video.contentLength + audio.contentLength }
}

/// Downloads a video for offline watching: the video track and the audio
/// track as separate files, then one passthrough remux into a single MP4.
///
/// One job at a time. Two parallel downloads on an A7 over one link finish no
/// sooner together than one after the other, and a queue is only worth
/// building once the Downloads screen exists to show it.
/// ponytail: single job; add a queue when the Downloads screen lands.
final class VideoDownloader {
    /// Posted while a download runs, at most once a second — enough for a
    /// percentage to look alive, few enough not to churn the main queue on an
    /// A7 while megabytes land.
    static let didProgressNotification = Notification.Name(
        "VideoDownloaderDidProgress"
    )
    private static let progressInterval: TimeInterval = 1

    static let shared = VideoDownloader()

    private(set) var activeVideoId: String?
    /// 0...1 across both tracks. Reads as 1 while the remux runs.
    private(set) var progress: Double = 0
    private(set) var isMuxing = false

    let transport: HTTPTransport
    private let apiClient: WatchService
    let client: PlaybackClient = VisionOSClient()
    var cancellation: CancellationToken?
    private var receivedBytes: Int64 = 0
    private var totalBytes: Int64 = 1
    private var lastProgressPost = Date.distantPast

    var isDownloading: Bool { activeVideoId != nil }

    init(
        transport: HTTPTransport = ServiceContainer.mediaTransport,
        apiClient: WatchService = ServiceContainer.watch
    ) {
        self.transport = transport
        self.apiClient = apiClient
    }

    // MARK: - Options

    /// Renditions this video can be saved at.
    ///
    /// The visionOS client, not the one playback happens to be on: it is the
    /// only anonymous client googlevideo still serves past the first minute
    /// (Opaline#76), and a download reads the whole file in one go.
    func options(
        for videoId: String,
        completion: @escaping (Result<[DownloadOption], Error>) -> Void
    ) {
        apiClient.fetchDirectPlayback(
            videoId: videoId,
            client: client,
            poToken: nil,
            cancellationToken: nil
        ) { result in
            completion(result.map { Self.options(in: $0) })
        }
    }

    // MARK: - Job control

    func start(
        videoId: String,
        option: DownloadOption,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard !isDownloading else {
            completion(.failure(DownloadError.busy))
            return
        }
        guard DownloadStore.prepareFolder(for: videoId) else {
            completion(.failure(DownloadError.storage))
            return
        }
        activeVideoId = videoId
        progress = 0
        isMuxing = false
        receivedBytes = 0
        totalBytes = max(option.bytes, 1)
        cancellation = CancellationToken()
        DownloadStore.announceChange()
        AppLog.downloads(
            "start \(videoId) \(option.label) \(option.bytes / 1_048_576) MB,"
                + " itags \(option.video.itag)+\(option.audio.itag)"
        )
        fetchTracks(videoId: videoId, option: option, completion: completion)
    }

    func cancel() {
        guard let videoId = activeVideoId else {
            return
        }
        cancellation?.cancel()
        finish(videoId: videoId)
        DownloadStore.removeParts(for: videoId)
        AppLog.downloads("cancelled \(videoId)")
        DownloadStore.announceChange()
    }

    private func fetchTracks(
        videoId: String,
        option: DownloadOption,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let videoPart = DownloadStore.partFile(for: videoId, named: "video.part.mp4")
        let audioPart = DownloadStore.partFile(for: videoId, named: "audio.part.mp4")
        download(
            from: option.video.url,
            to: videoPart,
            size: option.video.contentLength
        ) { [weak self] error in
            if let error {
                self?.fail(videoId: videoId, error: error, completion: completion)
                return
            }
            self?.download(
                from: option.audio.url,
                to: audioPart,
                size: option.audio.contentLength
            ) { audioError in
                if let audioError {
                    self?.fail(
                        videoId: videoId, error: audioError, completion: completion
                    )
                    return
                }
                self?.mux(
                    videoId: videoId,
                    option: option,
                    parts: (videoPart, audioPart),
                    completion: completion
                )
            }
        }
    }

    func fail(
        videoId: String,
        error: Error,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        AppLog.downloads("failed \(videoId): \(error)")
        let cancelled = cancellation?.isCancelled == true
        finish(videoId: videoId)
        DownloadStore.removeParts(for: videoId)
        DownloadStore.announceChange()
        guard !cancelled else {
            return
        }
        DispatchQueue.main.async { completion(.failure(error)) }
    }

    func finish(videoId: String) {
        guard activeVideoId == videoId else {
            return
        }
        activeVideoId = nil
        isMuxing = false
        progress = 0
        cancellation = nil
    }

    func advance(by count: Int64) {
        receivedBytes += count
        progress = min(Double(receivedBytes) / Double(totalBytes), 1)
        guard Date().timeIntervalSince(lastProgressPost)
            >= Self.progressInterval else {
            return
        }
        lastProgressPost = Date()
        postProgress()
    }

    func markMuxing() {
        isMuxing = true
        progress = 1
        postProgress()
    }

    /// Job state is read by the UI, so every transition lands on the main
    /// thread — chunks arrive on the transport's delivery queue and the
    /// export session finishes on its own.
    func postProgress() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didProgressNotification, object: nil
            )
        }
    }
}

enum DownloadError: LocalizedError {
    case busy
    case storage
    case http(Int)
    case noTracks
    case export
    case missingFile

    var errorDescription: String? {
        switch self {
        case .busy:
            return "downloads.error.busy".localized
        default:
            return "downloads.error.failed".localized
        }
    }
}
