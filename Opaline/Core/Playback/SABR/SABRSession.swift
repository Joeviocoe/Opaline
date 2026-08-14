import Foundation

/// A slice of one stream as the server delivered it, positioned by its byte
/// offset in the file the legacy URL would have served.
struct SABRSegment {
    let itag: Int
    let start: Int64
    let data: Data
    let isInit: Bool

    var end: Int64 { start + Int64(data.count) }
}

/// A read parked until the stream reaches it.
struct Waiter {
    let request: SABRReadRequest
    let completion: (Result<Data, Error>) -> Void
}

/// One byte-range read from a stream, with the timeline position it maps to.
struct SABRReadRequest {
    let itag: Int
    let offset: Int64
    let length: Int
    /// Where `offset` falls in the video, used to reposition after a seek.
    let timeMs: Int
}

/// One SABR playback session: POSTs `VideoPlaybackAbrRequest`, folds the UMP
/// response into a rolling buffer, and answers byte-range reads out of it.
///
/// Unlike the legacy URLs this replaces, nothing here expires after a minute —
/// the server keeps authorizing the stream for as long as we keep asking.
final class SABRSession {
    /// Rolling buffer ceiling. The iPad mini 2 is the target and the player
    /// itself only keeps 20-25s ahead, so holding more than this buys nothing
    /// and costs resident memory.
    static let bufferLimit = 14 * 1_024 * 1_024
    /// How far ahead of the playhead the session keeps fetching on its own.
    /// Without this the pump only ran when a read was already waiting, so every
    /// segment cost a full request round-trip and the player reported
    /// "no response for media file" while it waited.
    static let prefetchMs = 15_000
    /// Bytes kept behind the read position. Must cover a few segments: the
    /// player does re-request one it already fetched (after a timeout, say),
    /// and if that lands before the buffer the session mistakes it for a seek
    /// and restarts the stream — which made playback slower, causing more
    /// timeouts, causing more restarts.
    static let keepBehind = 4 * 1_024 * 1_024
    /// Consecutive responses that answer nobody before we call it a stall
    /// rather than looping forever.
    static let maxEmptyRounds = 8

    private let transport: HTTPTransport
    let url: URL
    private let ustreamerConfig: Data
    let audio: SabrFormatInfo
    let video: SabrFormatInfo
    private let queue = DispatchQueue(label: "com.ytvlite.sabr-session")

    /// Contiguous bytes per stream, keyed by itag.
    var buffers: [Int: StreamBuffer] = [:]
    /// Init segments, kept for the whole session — AVPlayer re-reads them.
    var initSegments: [Int: Data] = [:]
    var progress: [Int: SABRStreamProgress] = [:]
    var playbackCookie: Data?
    private var requestNumber = 0
    var waiting: [Waiter] = []
    var inFlight = false
    var emptyRounds = 0
    /// How far each stream has been read, so consumed bytes can be dropped.
    var readOffsets: [Int: Int64] = [:]
    /// Timeline position of the furthest read served, for the prefetch window.
    var lastServedMs = 0
    /// Whether the last response carried any media, for the stall guard.
    var sawMediaInLastResponse = false
    var reachedEnd = false

    init(
        transport: HTTPTransport,
        url: URL,
        ustreamerConfig: Data,
        audio: SabrFormatInfo,
        video: SabrFormatInfo
    ) {
        self.transport = transport
        self.url = url
        self.ustreamerConfig = ustreamerConfig
        self.audio = audio
        self.video = video
    }

    // MARK: - Public API

    /// Opens the session and returns the init segment of each stream — the
    /// `ftyp/moov/sidx` prefix AVPlayer needs before any media.
    /// `resumeAt` starts the stream at the playhead instead of at zero —
    /// switching quality mid-video otherwise streams the opening again while
    /// the player waits for the part it is actually on.
    func start(
        resumeAt: Int = 0,
        completion: @escaping (Result<[Int: Data], Error>) -> Void
    ) {
        queue.async {
            let body = SABRRequest.startup(
                ustreamerConfig: self.ustreamerConfig,
                audio: self.audio,
                video: self.video
            )
            self.send(body) { [weak self] result in
                guard let self else {
                    return
                }
                if case .failure(let error) = result {
                    completion(.failure(error))
                    return
                }
                let inits = self.collectedInits()
                guard inits[self.audio.itag] != nil, inits[self.video.itag] != nil else {
                    completion(.failure(SABRError.noInitSegment))
                    return
                }
                guard resumeAt > 0 else {
                    completion(.success(inits))
                    return
                }
                self.jump(to: resumeAt) { completion(.success(inits)) }
            }
        }
    }

    /// Repositions the stream, keeping the init segments already collected.
    private func jump(to timeMs: Int, completion: @escaping () -> Void) {
        resetBuffers()
        progress.removeAll()
        lastServedMs = timeMs
        let body = SABRRequest.jump(
            ustreamerConfig: ustreamerConfig,
            audio: audio,
            video: video,
            playerMs: timeMs
        )
        send(body) { _ in completion() }
    }

    private func collectedInits() -> [Int: Data] {
        let inits = initSegments
        AppLog.hls(
            "sabr inits: got \(inits.keys.sorted()) want [\(audio.itag), \(video.itag)]"
        )
        return inits
    }

    /// Bytes `offset..<offset+length` of `itag`, waiting for them if the
    /// session has not streamed that far yet.
    ///
    /// Readers never fetch: they park here and a single pump moves the stream
    /// forward. Letting each read drive its own request meant three concurrent
    /// segment fetches sent three identical continuations — the first answer
    /// had not landed yet, so all three carried the same buffered state and the
    /// server dutifully returned the same megabytes three times over.
    func read(
        _ request: SABRReadRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        queue.async {
            if let data = self.buffered(
                itag: request.itag, offset: request.offset, length: request.length
            ) {
                self.markRead(
                    itag: request.itag,
                    offset: request.offset,
                    length: request.length,
                    timeMs: request.timeMs
                )
                completion(.success(data))
                return
            }
            self.waiting.append(Waiter(request: request, completion: completion))
            self.pump()
        }
    }

    /// The request that should bring the missing bytes in: a fresh session when
    /// the player moved away from where the server is streaming, otherwise the
    /// next chunk of the one already running.
    func nextBody(for request: SABRReadRequest) -> Data? {
        // A retry of bytes already served must not restart the session: they
        // merely fell out of the buffer, and the stream itself is still valid.
        // Restarting on those threw away all progress, so the server resent the
        // opening segments, which made playback slower, which caused more
        // retries — the loop this guard exists to break.
        let seeking = needsSeek(itag: request.itag, offset: request.offset)
            && !isRetry(itag: request.itag, offset: request.offset)
        guard !seeking else {
            resetBuffers()
            progress.removeAll()
            reachedEnd = false
            lastServedMs = request.timeMs
            // Jump rather than start over: a startup request would stream from
            // the beginning of the video again, and the player would sit
            // waiting while the session ground its way back to the playhead.
            return SABRRequest.jump(
                ustreamerConfig: ustreamerConfig,
                audio: audio,
                video: video,
                playerMs: request.timeMs
            )
        }
        return reachedEnd ? nil : continuationBody(timeMs: request.timeMs)
    }

    private func continuationBody(timeMs: Int) -> Data? {
        guard let audioProgress = progress[audio.itag],
              let videoProgress = progress[video.itag] else {
            return nil
        }
        AppLog.hls(
            "sabr continue: playerMs=\(timeMs)"
                + " audio(seq=\(audioProgress.lastSequence), buf=\(audioProgress.bufferedMs))"
                + " video(seq=\(videoProgress.lastSequence), buf=\(videoProgress.bufferedMs))"
                + " cookie=\(playbackCookie?.count ?? -1)"
        )
        return SABRRequest.continuation(
            ustreamerConfig: ustreamerConfig,
            state: SABRRequest.Continuation(
                audio: audioProgress,
                video: videoProgress,
                playerMs: timeMs,
                playbackCookie: playbackCookie
            )
        )
    }

    // MARK: - Transport

    func send(_ body: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        requestNumber += 1
        let request = HTTPRequest(
            method: .post,
            // The streaming URL always carries a query, so appending is safe.
            url: URL(string: "\(url.absoluteString)&rn=\(requestNumber)") ?? url,
            headers: [
                "Content-Type": "application/x-protobuf",
                "User-Agent": DirectPlaybackClient.androidVR.userAgent
            ],
            body: body,
            // Anonymous, like the spike this ports: cookies were tried on
            // device and changed nothing.
            sendsCookies: false
        )
        let sent = body.count
        transport.send(request, cancellationToken: nil) { [weak self] result in
            self?.queue.async {
                self?.handle(result, sent: sent, completion: completion)
            }
        }
    }

    private func handle(
        _ result: Result<HTTPResponse, Error>,
        sent: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            AppLog.hls("sabr request failed: \(error.localizedDescription)")
            completion(.failure(error))
        case .success(let response):
            AppLog.hls(
                "sabr #\(requestNumber) sent \(sent)B"
                    + " -> HTTP \(response.status), \(response.data.count)B"
            )
            completion(consume(response))
        }
    }
}

enum SABRError: LocalizedError {
    case noInitSegment
    case stalled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noInitSegment:
            "SABR returned no init segment"
        case .stalled:
            "SABR stopped returning media"
        case .server(let detail):
            "SABR error: \(detail)"
        }
    }
}
