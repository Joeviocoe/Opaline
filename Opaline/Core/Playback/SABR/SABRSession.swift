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
    /// Which segment this is, counting from 1 as SABR does. A jump claims
    /// everything up to the target is buffered, and claiming 30 minutes of it
    /// while saying "last segment: 1" is contradictory enough that the server
    /// answers with policy and no media.
    let sequence: Int
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
    /// How far ahead of the stream a read may land before the session
    /// repositions rather than streaming its way there. Must stay above the
    /// player's own read-ahead (20s of buffer plus a segment), or ordinary
    /// playback would be mistaken for a seek and restart the stream.
    static let seekAheadMs = 45_000
    /// Consecutive responses that answer nobody before we call it a stall
    /// rather than looping forever.
    static let maxEmptyRounds = 8

    private let transport: HTTPTransport
    let url: URL
    let ustreamerConfig: Data
    let audio: SabrFormatInfo
    let video: SabrFormatInfo
    /// Who this session streams as — client and po token.
    let identity: SABRIdentity
    let queue = DispatchQueue(label: "com.ytvlite.sabr-session")

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
        video: SabrFormatInfo,
        identity: SABRIdentity
    ) {
        self.transport = transport
        self.url = url
        self.ustreamerConfig = ustreamerConfig
        self.audio = audio
        self.video = video
        self.identity = identity
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
        let seeking = (needsSeek(itag: request.itag, offset: request.offset)
            && !isRetry(itag: request.itag, offset: request.offset))
            || isAheadOfStream(request)
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
                identity: identity,
                playerMs: request.timeMs,
                sequence: request.sequence
            )
        }
        return reachedEnd ? nil : continuationBody(timeMs: request.timeMs)
    }

    private func continuationBody(timeMs: Int) -> Data? {
        guard let audioProgress = progress[audio.itag],
              let videoProgress = progress[video.itag] else {
            return nil
        }
        return SABRRequest.continuation(
            ustreamerConfig: ustreamerConfig,
            state: SABRRequest.Continuation(
                audio: audioProgress,
                video: videoProgress,
                playerMs: timeMs,
                playbackCookie: playbackCookie
            ),
            identity: identity
        )
    }

    // MARK: - Transport
    private func sabrHeaders() -> [String: String] {
        var headers = [HTTPHeader.contentType: "application/x-protobuf"]
        headers[HTTPHeader.userAgent] = identity.client.userAgent
        return headers
    }

    func send(_ body: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        requestNumber += 1
        let request = HTTPRequest(
            method: .post,
            // The streaming URL always carries a query, so appending is safe.
            url: URL(string: "\(url.absoluteString)&rn=\(requestNumber)") ?? url,
            headers: sabrHeaders(),
            body: body,
            // Anonymous, like the spike this ports: cookies were tried on
            // device and changed nothing.
            sendsCookies: false,
            isPlayback: true
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
        case .success(let response) where response.status != 200:
            // A refusal with no body never reaches the SABR protocol at all —
            // googlevideo rejected the URL itself. The request is NOT logged:
            // it carries the signed URL and the po token.
            AppLog.hls("sabr HTTP \(response.status) refused, sent \(sent)B")
            completion(consume(response))
        case .success(let response):
            AppLog.hls(
                "sabr #\(requestNumber) sent \(sent)B"
                    + " -> HTTP \(response.status), \(response.data.count)B"
            )
            completion(consume(response))
        }
    }
}
