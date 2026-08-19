import Foundation

/// One downloadable rendition, as offered by the quality prompt.
struct DownloadOption {
    let label: String
    let height: Int
    let video: DashFormatInfo
    let audio: DashFormatInfo

    var bytes: Int64 { video.contentLength + audio.contentLength }
}

/// Downloads videos for offline watching: the video track and the audio track
/// as separate files, then one passthrough remux into a single MP4.
///
/// One job runs at a time and the rest wait. Two transfers over one link
/// finish no sooner together than one after the other, and a queue is what a
/// list screen needs anyway once "Download" sits in the menu of every row.
final class VideoDownloader {
    /// One video waiting to be saved.
    struct Job {
        let video: Video
        let option: DownloadOption
        let completion: (Result<URL, Error>) -> Void
        /// How many times this job has already been retried after a network
        /// failure.
        var attempt = 0
    }

    /// Posted while a download runs, at most once a second — enough for a
    /// percentage to look alive, few enough not to churn the main queue on an
    /// A7 while megabytes land.
    static let didProgressNotification = Notification.Name(
        "VideoDownloaderDidProgress"
    )
    private static let progressInterval: TimeInterval = 1

    static let shared = VideoDownloader()

    /// 0...1 across both tracks of the running job. Reads as 1 while the
    /// remux runs.
    private(set) var progress: Double = 0
    private(set) var isMuxing = false

    let transport: HTTPTransport
    let client: PlaybackClient = VisionOSClient()
    var cancellation: CancellationToken?

    private let apiClient: WatchService
    private(set) var jobs: [Job] = []
    private var receivedBytes: Int64 = 0
    private var totalBytes: Int64 = 1
    private var lastProgressPost = Date.distantPast

    var activeVideo: Video? { jobs.first?.video }
    var activeVideoId: String? { jobs.first?.video.id }
    /// How many are waiting behind the one running.
    var queuedCount: Int { max(jobs.count - 1, 0) }
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

    // MARK: - Queue

    func isQueued(_ videoId: String) -> Bool {
        jobs.contains { $0.video.id == videoId }
    }

    func start(
        video: Video,
        option: DownloadOption,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard !isQueued(video.id) else {
            completion(.failure(DownloadError.busy))
            return
        }
        guard DownloadStore.prepareFolder(for: video.id) else {
            completion(.failure(DownloadError.storage))
            return
        }
        DownloadStore.clearFailure(video.id)
        DownloadStore.save(video)
        fetchThumbnail(for: video)
        jobs.append(
            Job(video: video, option: option, completion: completion)
        )
        DownloadStore.announceChange()
        if jobs.count == 1 {
            startNextJob()
        }
    }

    /// Drops the running job and moves on to whatever is behind it.
    func cancel() {
        guard let job = jobs.first else {
            return
        }
        cancellation?.cancel()
        AppLog.downloads("cancelled \(job.video.id)")
        // The whole folder, not just the parts: the metadata was written when
        // the download was asked for, and leaving it behind would keep an
        // empty card on the Downloads screen forever.
        DownloadStore.remove(job.video.id)
        finishJob(reporting: nil)
    }

    /// Cancels one video wherever it sits: running, or still waiting its turn.
    func cancel(_ videoId: String) {
        guard activeVideoId != videoId else {
            cancel()
            return
        }
        guard let index = jobs.firstIndex(where: { $0.video.id == videoId })
        else {
            return
        }
        jobs.remove(at: index)
        AppLog.downloads("dequeued \(videoId)")
        DownloadStore.remove(videoId)
    }

    private func startNextJob() {
        guard let job = jobs.first else {
            return
        }
        let option = job.option
        progress = 0
        isMuxing = false
        totalBytes = max(option.bytes, 1)
        receivedBytes = 0
        cancellation = CancellationToken()
        DownloadStore.announceChange()
        AppLog.downloads(
            "start \(job.video.id) \(option.label)"
                + " \(option.bytes / 1_048_576) MB,"
                + " itags \(option.video.itag)+\(option.audio.itag)"
        )
        fetchTracks(videoId: job.video.id, option: option)
    }

    func bumpAttempt() {
        guard !jobs.isEmpty else {
            return
        }
        jobs[0].attempt += 1
    }

    /// After a resume, progress must count what is already on disk, or a job
    /// that is half done would report starting from zero.
    func resetProgressToDisk(videoId: String) {
        receivedBytes = bytesAlreadySaved(videoId: videoId)
        progress = min(Double(receivedBytes) / Double(totalBytes), 1)
        postProgress()
    }

    /// Ends the running job, tells its caller how it went, and starts the
    /// next. A cancelled job reports nothing: its caller asked for this.
    func finishJob(reporting result: Result<URL, Error>?) {
        guard !jobs.isEmpty else {
            return
        }
        let job = jobs.removeFirst()
        isMuxing = false
        progress = 0
        cancellation = nil
        DownloadStore.announceChange()
        if let result {
            DispatchQueue.main.async { job.completion(result) }
        }
        startNextJob()
    }

    // MARK: - Progress

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
