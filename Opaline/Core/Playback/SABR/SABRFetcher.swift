import Foundation

/// One segment as the client asks for it.
struct SABRSegmentRequest {
    let format: SabrFormatInfo
    /// The other stream, named so the server can be told not to send it.
    let other: SabrFormatInfo
    /// Segment number, counting from 1 as SABR does.
    let sequence: Int
    /// Where the segment starts in the video, which is where the server is
    /// asked to stream from. A seek is nothing more than a different value
    /// here — there is no separate seek request in this protocol.
    let timeMs: Int
    /// Init segments name a byte range of the opening; media segments take
    /// whatever the server sends for the sequence.
    let initRange: Int?

    var isInit: Bool { initRange != nil }
}

/// Fetches SABR media one segment at a time.
///
/// This mirrors how googlevideo's own player adapter works, and it is the
/// whole design: a player's request for a segment becomes one
/// `VideoPlaybackAbrRequest`, the response is read until the segment it asked
/// for is complete, and the rest of the response is dropped. There is no
/// rolling buffer, no prefetch and no notion of the stream being "at" a
/// position — the player's own buffering does that job, and every request
/// states afresh where it wants bytes from.
///
/// What persists between requests is only what the server needs to keep the
/// session coherent: the last segment seen per format, the playback cookie and
/// the backoff it asked for.
final class SABRFetcher {
    /// What one request needs from the shared state, taken under a single
    /// lock: its number, what is held of this format, and the cookie.
    private struct RequestState {
        let number: Int
        let held: SABRBufferedRange?
        let cookie: Data?
    }

    private let transport: HTTPTransport
    let url: URL
    let ustreamerConfig: Data
    let identity: SABRIdentity

    /// Guards everything below; requests run concurrently, one per segment,
    /// and audio and video are routinely in flight together.
    private let lock = NSLock()
    private var lastSegment: [Int: SABRBufferedRange] = [:]
    private var lastRequestedMs: [Int: Int] = [:]
    private var playbackCookie: Data?
    private var backoffUntil = Date.distantPast
    private var requestNumber = 0
    private var stopped = false

    init(
        transport: HTTPTransport,
        url: URL,
        ustreamerConfig: Data,
        identity: SABRIdentity
    ) {
        self.transport = transport
        self.url = url
        self.ustreamerConfig = ustreamerConfig
        self.identity = identity
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    /// The bytes of one segment, or an error. Runs one POST; the response is
    /// abandoned as soon as the segment is complete.
    func fetch(
        _ request: SABRSegmentRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        lock.lock()
        let stopped = self.stopped
        let wait = backoffUntil.timeIntervalSinceNow
        lock.unlock()
        guard !stopped else {
            completion(.failure(SABRError.stalled))
            return
        }
        guard wait <= 0 else {
            // The server asked for a pause; honouring it is cheaper than being
            // told again.
            DispatchQueue.global(qos: .userInitiated)
                .asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.fetch(request, completion: completion)
                }
            return
        }
        send(request, completion: completion)
    }

    private func send(
        _ request: SABRSegmentRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let collector = SABRSegmentCollector(request: request)
        let started = Date()
        transport.stream(httpRequest(for: request), cancellationToken: nil) { [weak self] chunk in
            self?.consume(chunk, with: collector)
            // Stop the moment the segment is whole: the rest of the response is
            // the stream running on past what this request was about.
            return !collector.isDone
        } completion: { [weak self] result in
            self?.finish(result, collector: collector, started: started, completion: completion)
        }
    }

    private func consume(_ chunk: Data, with collector: SABRSegmentCollector) {
        guard !collector.isDone else {
            return
        }
        collector.append(chunk)
    }

    private func finish(
        _ result: Result<HTTPResponse, Error>,
        collector: SABRSegmentCollector,
        started: Date,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        apply(collector.policy)
        if let range = collector.deliveredRange {
            lock.lock()
            lastSegment[collector.request.format.itag] = range
            lock.unlock()
        }
        if case .failure(let error) = result, !collector.isDone {
            completion(.failure(error))
            return
        }
        if case .success(let response) = result, response.status != 200, !collector.isDone {
            // A refusal never reaches the SABR protocol: googlevideo rejected
            // the URL itself. Not logged with the URL — it carries the po token.
            completion(.failure(SABRError.server("HTTP \(response.status)")))
            return
        }
        if let failure = collector.failure {
            completion(.failure(failure))
            return
        }
        guard let data = collector.segment else {
            AppLog.hls("sabr \(collector.label): no media in \(collector.received)B")
            completion(.failure(SABRError.stalled))
            return
        }
        let ms = Int(Date().timeIntervalSince(started) * 1_000)
        AppLog.hls(
            "sabr \(collector.label) -> \(data.count)B of \(collector.received)B in \(ms)ms"
        )
        completion(.success(data))
    }

    private func apply(_ policy: SABRPolicy?) {
        guard let policy else {
            return
        }
        lock.lock()
        if let cookie = policy.playbackCookie {
            playbackCookie = cookie
        }
        if policy.backoffMs > 0 {
            backoffUntil = Date().addingTimeInterval(Double(policy.backoffMs) / 1_000)
            AppLog.hls("sabr backoff \(policy.backoffMs)ms")
        }
        lock.unlock()
    }

    private func stateFor(_ request: SABRSegmentRequest) -> RequestState {
        lock.lock()
        defer { lock.unlock() }
        requestNumber += 1
        let itag = request.format.itag
        // A request behind the last one is the player having moved back, and
        // what was last received no longer describes where it is. googlevideo's
        // adapter drops the same state on the same condition.
        if request.timeMs < lastRequestedMs[itag] ?? 0 {
            lastSegment[itag] = nil
        }
        lastRequestedMs[itag] = request.timeMs
        return RequestState(
            number: requestNumber, held: lastSegment[itag], cookie: playbackCookie
        )
    }

    private func httpRequest(for request: SABRSegmentRequest) -> HTTPRequest {
        let state = stateFor(request)
        var headers = [HTTPHeader.contentType: "application/x-protobuf"]
        headers[HTTPHeader.userAgent] = identity.client.userAgent
        return HTTPRequest(
            method: .post,
            // The streaming URL always carries a query, so appending is safe.
            url: URL(string: "\(url.absoluteString)&rn=\(state.number)") ?? url,
            headers: headers,
            body: SABRRequest.segment(
                ustreamerConfig: ustreamerConfig,
                state: SABRRequest.Fetch(
                    format: request.format,
                    other: request.other,
                    held: state.held,
                    isInit: request.isInit,
                    playerMs: request.timeMs,
                    playbackCookie: state.cookie
                ),
                identity: identity
            ),
            // One segment is seconds of media; a request still running after
            // this is one the player gave up on long ago.
            timeout: 20,
            // Anonymous: cookies were tried on device and changed nothing.
            sendsCookies: false,
            isPlayback: true
        )
    }
}
