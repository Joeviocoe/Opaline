import Darwin
import QuartzCore
import Foundation

/// A minimal HTTP/1.1 server on 127.0.0.1 that proxies googlevideo streams.
///
/// **Why this exists.** `AVMutableComposition` will not compose an asset backed
/// by an `AVAssetResourceLoaderDelegate` on a custom scheme: measured on an
/// iPad 3, the tracks load and then `insertTimeRange` fails with
/// AVFoundationErrorDomain -11801 / NSOSStatusErrorDomain -12786, even once the
/// whole stream has been fetched. Composition wants a real, randomly
/// addressable asset. Handing AVFoundation an ordinary `http://127.0.0.1/…` URL
/// gives it exactly that.
///
/// It also solves the problem that made the resource loader necessary in the
/// first place: googlevideo cuts off an open-ended GET after roughly a
/// megabyte, so each upstream fetch here is bounded and the pieces are streamed
/// out as one continuous response.
///
/// Network.framework is iOS 12, so this is BSD sockets. It listens only on the
/// loopback interface and serves only paths registered with it, so nothing
/// outside the app can reach it.
final class LegacyLoopbackServer {
    /// One stream this server will serve, under `/<id>`.
    struct Stream {
        let url: URL
        let headers: [String: String]
        let contentLength: Int64
        let contentType: String
    }

    static let shared = LegacyLoopbackServer()

    /// Upstream fetch size, adaptive.
    ///
    /// AVFoundation walks a fragmented MP4 by seeking: it opens a range, reads a
    /// fragment header, and closes. Measured on the device, dozens of those
    /// probes across a 78 MB video — each one closing after a single chunk.
    /// Fetching a flat 900 KB per probe meant ~878 KB of waste and a full
    /// round-trip before a single byte reached the player, which is where the
    /// startup delay came from.
    ///
    /// So start small and grow: a probe costs one small fetch, while a
    /// connection that keeps reading ramps up to the efficient size within a few
    /// chunks. The ceiling stays under googlevideo's ~1 MiB throttle window.
    private static let firstChunk: Int64 = 64 * 1024
    private static let maxChunk: Int64 = 900_000

    /// A contiguous window of one stream, held in memory.
    ///
    /// AVFoundation walks a fragmented MP4 forward in small steps — measured on
    /// the device at ~174 seeks across a 78 MB video, monotonically increasing.
    /// Without a cache every step is its own upstream round-trip, and at ~200 ms
    /// each that is ~35 s of pure latency before playback can start. Bandwidth
    /// was never the constraint, which is why shrinking the chunk size did not
    /// help.
    ///
    /// One window per stream, refilled forward. A seek backwards or far ahead
    /// simply repositions it.
    private final class Window {
        var start: Int64 = 0
        var data = Data()
        /// Grows while the reader keeps running off the end of the window in
        /// order, shrinks back when it jumps somewhere else.
        var size: Int64 = LegacyLoopbackServer.minWindow
        var end: Int64 { start + Int64(data.count) }

        func contains(_ offset: Int64) -> Bool {
            offset >= start && offset < end
        }

        func slice(from offset: Int64, max count: Int) -> Data {
            let index = Int(offset - start)
            return data.subdata(in: index..<min(index + count, data.count))
        }
    }

    /// Refill size, adaptive per stream.
    ///
    /// A flat 6 MB was badly wrong during indexing: AVFoundation reads a few KB
    /// past a primed fragment header, misses, and pulls six megabytes to serve
    /// it. Four such misses was 24 MB of the 37 MB measured — and at the
    /// device's ~1.2 MB/s that was 18 of the 23 seconds to first frame.
    ///
    /// So start small, and grow only while reads stay sequential — indexing gets
    /// cheap misses, playback still gets big efficient refills.
    private static let minWindow: Int64 = 256 * 1024
    /// 8 MB once a read is clearly sequential. Sustained playback needs only
    /// ~46 KB/s (84 MB over 30 minutes), so reading further ahead costs almost
    /// nothing and buys a large cushion against the per-request round trip that
    /// showed up as jitter.
    private static let maxWindow: Int64 = 8 * 1024 * 1024

    private var windows: [String: Window] = [:]
    /// Fragment headers fetched ahead of time, keyed by their start offset.
    ///
    /// AVFoundation's walk visits the head of every segment. Those are known
    /// from the `sidx` before playback begins, so they are fetched here — in
    /// parallel, which is the whole point: serially they would cost the same
    /// ~174 round-trips that made the walk slow in the first place.
    private var primed: [String: [Int64: Data]] = [:]
    /// Streams being served as synthesized progressive MP4s rather than
    /// proxied verbatim. The player sees one `moov` and streams; it never walks
    /// the fragments.
    private var remuxes: [String: LegacyProgressiveRemux.Remuxed] = [:]
    private var streams: [String: Stream] = [:]
    /// Builds a response body for a path, for callers that generate bytes
    /// rather than proxy them. SABR needs this: its playlists and transmuxed
    /// segments exist only in memory, so there is no upstream URL to publish.
    typealias DynamicHandler = (
        _ path: String,
        _ completion: @escaping (Data?, String) -> Void
    ) -> Void
    private var dynamicHandler: DynamicHandler?
    /// Bytes actually served per stream, so "how much did AVFoundation demand
    /// before it would play?" is a measured number rather than a guess.
    private var served: [String: Int64] = [:]
    /// Rolling (timestamp, cumulative bytes) samples for a recent-throughput
    /// figure. `AVPlayerItem.accessLog()` is empty for a composition — its asset
    /// is not something AVFoundation fetched — so stats-for-nerds reported no
    /// speed and no transfer at all. The server knows both first-hand, and its
    /// numbers are the real upstream rate rather than the player's estimate.
    private var rateSamples: [(at: CFTimeInterval, bytes: Int64)] = []
    private var servedTotal: Int64 = 0
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "opaline.loopback", attributes: .concurrent)

    /// Registers a stream and returns the loopback URL for it. Starts the
    /// server on first use.
    func publish(_ stream: Stream, as id: String) -> URL? {
        guard start() else {
            return nil
        }
        lock.lock()
        streams[id] = stream
        served[id] = 0
        windows[id] = Window()
        primed[id] = [:]
        lock.unlock()
        return URL(string: "http://127.0.0.1:\(port)/\(id)")
    }

    /// Stops serving a stream. In-flight connections notice on their next
    /// chunk and end the response, which is what stops an abandoned playback
    /// attempt from downloading in the background forever.
    /// Total bytes this server has fetched upstream, for the stats overlay.
    /// Registers the generated-content handler and returns the server base.
    func publishHandler(_ handler: @escaping DynamicHandler) -> URL? {
        guard start() else {
            return nil
        }
        lock.lock()
        dynamicHandler = handler
        lock.unlock()
        let base = URL(string: "http://127.0.0.1:\(port)/")
        AppLog.player(
            "loopback: dynamic handler registered at \(base?.absoluteString ?? "?")"
        )
        return base
    }

    func withdrawHandler() {
        lock.lock()
        dynamicHandler = nil
        lock.unlock()
    }

    func totalBytesServed() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return servedTotal
    }

    /// Recent upstream throughput in bits per second, or nil when there is not
    /// enough history to say.
    func recentBitsPerSecond() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let first = rateSamples.first, let last = rateSamples.last else {
            return nil
        }
        let seconds = last.at - first.at
        guard seconds > 0.5 else {
            return nil
        }
        return Double(last.bytes - first.bytes) * 8 / seconds
    }

    /// Fetched fragment headers, so the remuxer can parse what priming pulled
    /// rather than fetching it twice.
    func primedData(_ id: String) -> [Int64: Data] {
        lock.lock()
        defer { lock.unlock() }
        return primed[id] ?? [:]
    }

    /// Serves this stream as the given progressive file from now on.
    func attachRemux(_ remuxed: LegacyProgressiveRemux.Remuxed, to id: String) {
        lock.lock()
        remuxes[id] = remuxed
        lock.unlock()
        AppLog.player(
            "loopback[\(id.suffix(2))]: serving progressive MP4 —"
                + " \(remuxed.header.count / 1024) KB header,"
                + " \(remuxed.mediaRanges.count) media ranges,"
                + " \(remuxed.totalLength / 1_048_576) MB total"
        )
    }

    func withdraw(_ id: String) {
        lock.lock()
        streams.removeValue(forKey: id)
        let bytes = served.removeValue(forKey: id) ?? 0
        windows.removeValue(forKey: id)
        primed.removeValue(forKey: id)
        remuxes.removeValue(forKey: id)
        lock.unlock()
        AppLog.player("loopback: withdrew \(id) after \(bytes / 1024) KB served")
    }

    /// Bytes served so far for a stream, for logging at the moment playback
    /// becomes ready.
    func bytesServed(_ id: String) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return served[id] ?? 0
    }

    // MARK: - Listening

    @discardableResult
    private func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if listenFD >= 0 {
            return true
        }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            AppLog.player("loopback: socket() failed, errno \(errno)")
            return false
        }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Writing to a socket the player has closed must return EPIPE, not kill
        // the process with SIGPIPE.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral; the kernel picks a free one
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            AppLog.player("loopback: bind/listen failed, errno \(errno)")
            close(fd)
            return false
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        port = UInt16(bigEndian: actual.sin_port)
        listenFD = fd
        AppLog.player("loopback: listening on 127.0.0.1:\(port)")

        queue.async { [weak self] in self?.acceptLoop(fd) }
        return true
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var yes: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes,
                       socklen_t(MemoryLayout<Int32>.size))
            queue.async { [weak self] in
                self?.serve(client)
                close(client)
            }
        }
    }

    // MARK: - Serving one request

    /// Serves a body built on demand by the dynamic handler.
    ///
    /// The handler is asynchronous and this runs on a socket thread, so it waits
    /// on a semaphore. The timeout matters: without one a handler that never
    /// calls back would hold a worker thread for the life of the app, and the
    /// symptom would be playback that simply stops answering.
    private func serveGenerated(
        _ client: Int32,
        path: String,
        rangeHeader: String?,
        isHead: Bool,
        handler: @escaping DynamicHandler
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?
        var type = ""
        handler(path) { data, contentType in
            body = data
            type = contentType
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            AppLog.player("loopback: handler timed out for \(path)")
            _ = send(client, "HTTP/1.1 504 Gateway Timeout\r\nContent-Length: 0\r\n\r\n")
            return
        }
        guard let body = body, !body.isEmpty else {
            AppLog.player("loopback: handler had nothing for \(path)")
            _ = send(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            return
        }
        let total = Int64(body.count)
        var start: Int64 = 0
        var end: Int64 = total - 1
        var partial = false
        if let header = rangeHeader, let parsed = Self.parseRange(header, total: total) {
            start = parsed.0
            end = parsed.1
            partial = true
        }
        guard start <= end, start < total else {
            _ = send(client, "HTTP/1.1 416 Range Not Satisfiable\r\n"
                + "Content-Range: bytes */\(total)\r\nContent-Length: 0\r\n\r\n")
            return
        }
        var head = partial
            ? "HTTP/1.1 206 Partial Content\r\n"
            : "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        if partial {
            head += "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
        }
        head += "Content-Length: \(end - start + 1)\r\n\r\n"
        AppLog.player(
            "loopback: \(isHead ? "HEAD" : "GET") \(path)"
                + " -> \(end - start + 1) of \(total) bytes \(type)"
        )
        guard send(client, head) else { return }
        if isHead { return }
        let lower = body.startIndex + Int(start)
        let upper = body.startIndex + Int(end) + 1
        _ = sendBody(client, body.subdata(in: lower..<upper))
        lock.lock()
        servedTotal += end - start + 1
        lock.unlock()
    }

    private func serve(_ client: Int32) {
        guard let request = readRequest(client) else {
            return
        }
        let (path, rangeHeader, isHead) = request
        lock.lock()
        let stream = streams[path]
        lock.unlock()
        if stream == nil {
            lock.lock()
            let handler = dynamicHandler
            lock.unlock()
            if let handler = handler {
                serveGenerated(
                    client, path: path, rangeHeader: rangeHeader,
                    isHead: isHead, handler: handler
                )
                return
            }
        }
        guard let stream = stream else {
            AppLog.player("loopback: 404 for \(path)")
            _ = send(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            return
        }

        lock.lock()
        let remux = remuxes[path]
        lock.unlock()
        let total = remux?.totalLength ?? stream.contentLength
        var start: Int64 = 0
        var end: Int64 = total - 1
        if let header = rangeHeader, let parsed = Self.parseRange(header, total: total) {
            start = parsed.0
            end = parsed.1
        }
        guard start <= end, start < total else {
            _ = send(client, "HTTP/1.1 416 Range Not Satisfiable\r\n"
                + "Content-Range: bytes */\(total)\r\nContent-Length: 0\r\n\r\n")
            return
        }

        let length = end - start + 1
        let openedAt = CACurrentMediaTime()
        AppLog.player(
            "loopback[\(path.suffix(2))]: \(isHead ? "HEAD" : "GET")"
                + " \(start)-\(end) of \(total)"
                + (remux == nil ? " [raw]" : " [progressive]")
                + (rangeHeader == nil ? " (no range)" : "")
        )
        var head = rangeHeader == nil
            ? "HTTP/1.1 200 OK\r\n"
            : "HTTP/1.1 206 Partial Content\r\n"
        head += "Content-Type: \(stream.contentType)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += "Content-Length: \(length)\r\n"
        if rangeHeader != nil {
            head += "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        guard send(client, head), !isHead else {
            return
        }

        // Stream the body in bounded upstream fetches. A client that stops
        // reading (AVFoundation has what it needs) fails the write and ends the
        // response early, which is normal and not an error.
        var offset = start
        var chunk = Self.firstChunk
        while offset <= end {
            // Withdrawn means the playback attempt was abandoned; stop rather
            // than keep pulling megabytes nobody is waiting for.
            lock.lock()
            let live = streams[path] != nil
            lock.unlock()
            guard live else {
                return
            }
            let data: Data?
            if let remux = remux {
                data = remuxedBytes(
                    remux, stream: stream, id: path,
                    from: offset, upTo: end, want: Int(chunk)
                )
            } else {
                data = windowedBytes(
                    stream, id: path, from: offset, upTo: end, want: Int(chunk)
                )
            }
            guard let data = data else {
                return
            }
            guard sendBody(client, data) else {
                AppLog.player(
                    "loopback[\(path.suffix(2))]: client closed after"
                        + " \(Int((offset - start) / 1024)) KB (normal)"
                )
                return
            }
            offset += Int64(data.count)
            // The client is still reading, so this is a real transfer rather
            // than a probe: fetch more per round-trip from here on.
            chunk = min(chunk * 2, Self.maxChunk)
            lock.lock()
            served[path, default: 0] += Int64(data.count)
            servedTotal += Int64(data.count)
            let now = CACurrentMediaTime()
            rateSamples.append((at: now, bytes: servedTotal))
            // Five seconds of history is enough for a live rate and keeps this
            // from growing without bound over a long video.
            while let first = rateSamples.first, now - first.at > 5 {
                rateSamples.removeFirst()
            }
            lock.unlock()
            if data.isEmpty {
                return
            }
        }
        // Interpolation, not String(format:): passing an Int64 to %d corrupts the
        // varargs on armv7, which printed a negative duration and a rate with
        // 200-odd digits.
        let seconds = max(CACurrentMediaTime() - openedAt, 0.001)
        let kb = Int((offset - start) / 1024)
        let rate = Double(offset - start) / seconds / 1_048_576
        AppLog.player(
            "loopback[\(path.suffix(2))]: served \(kb) KB in"
                + " \(String(format: "%.1f", seconds))s"
                + " (\(String(format: "%.1f", rate)) MB/s)"
        )
    }

    /// Fetches the given ranges up front, in parallel, into the primed cache.
    ///
    /// Called with the head of every segment from the `sidx`. ~234 ranges of a
    /// few KB each: serially that is 234 round-trips and no better than letting
    /// AVFoundation do the walking, so they go out concurrently and the whole
    /// index lands in a couple of seconds instead of forty.
    /// Concurrency is deliberately low. These are small requests, so the win
    /// comes from overlapping latency rather than from saturating the link, and
    /// a wide burst of ranged requests is exactly the shape that gets a visitor
    /// identity throttled. googlevideo has already cut us off once in testing
    /// (`upstream HTTP 0` across every connection at once), so four at a time,
    /// which still turns ~40 s of serial round-trips into a couple of seconds.
    func prime(_ id: String, ranges: [(Int64, Int64)], concurrency: Int = 6) {
        lock.lock()
        let stream = streams[id]
        lock.unlock()
        guard let stream = stream, !ranges.isEmpty else {
            return
        }
        let started = CACurrentMediaTime()
        let gate = DispatchSemaphore(value: concurrency)
        let group = DispatchGroup()
        var total = 0
        let totalLock = NSLock()

        for (start, end) in ranges {
            group.enter()
            gate.wait()
            queue.async { [weak self] in
                defer {
                    gate.signal()
                    group.leave()
                }
                guard let self = self else { return }
                guard let data = self.fetch(stream, from: start, to: end) else { return }
                self.lock.lock()
                self.primed[id]?[start] = data
                self.lock.unlock()
                totalLock.lock()
                total += data.count
                totalLock.unlock()
            }
        }
        group.wait()
        let seconds = CACurrentMediaTime() - started
        // Rate matters as much as the total: priming scales with video length
        // (68 fragments for a 14-minute video, 279 for a longer one), so a slow
        // per-request rate turns into a long wait on exactly the videos where it
        // is least welcome.
        AppLog.player(
            "loopback[\(id.suffix(2))]: primed \(ranges.count) fragment headers,"
                + " \(total / 1024) KB in \(String(format: "%.1f", seconds))s"
                + " (\(String(format: "%.0f", Double(ranges.count) / max(seconds, 0.001)))/s)"
        )
    }

    /// Bytes of the synthesized progressive file.
    ///
    /// Below the header length the answer is in memory; above it, the offset is
    /// mapped through the media ranges back to the original stream and fetched
    /// like any other read. The media itself is never copied or rewritten —
    /// only the index in front of it is new.
    private func remuxedBytes(
        _ remux: LegacyProgressiveRemux.Remuxed,
        stream: Stream,
        id: String,
        from offset: Int64,
        upTo end: Int64,
        want: Int
    ) -> Data? {
        let headerLength = Int64(remux.header.count)
        if offset < headerLength {
            let index = Int(offset)
            let count = min(want, min(remux.header.count - index, Int(end - offset + 1)))
            return remux.header.subdata(in: index..<(index + count))
        }
        var mediaOffset = offset - headerLength
        for range in remux.mediaRanges {
            if mediaOffset < range.length {
                let originOffset = range.origin + mediaOffset
                let available = min(Int64(want), range.length - mediaOffset)
                return windowedBytes(
                    stream, id: id,
                    from: originOffset,
                    upTo: originOffset + available - 1,
                    want: Int(available)
                )
            }
            mediaOffset -= range.length
        }
        return Data()
    }

    /// Bytes for a request, from the stream's window, refilling it when needed.
    ///
    /// This is what turns ~174 upstream round-trips into a handful. A read that
    /// lands inside the window costs nothing; one that runs past it refills
    /// forward with a single large fetch.
    private func windowedBytes(
        _ stream: Stream,
        id: String,
        from offset: Int64,
        upTo end: Int64,
        want: Int
    ) -> Data? {
        lock.lock()
        let window = windows[id]
        lock.unlock()
        guard let window = window else {
            // Withdrawn mid-flight.
            return nil
        }

        // A primed fragment header covering this offset costs no network at all.
        lock.lock()
        let hit = primed[id]?.first { start, data in
            offset >= start && offset < start + Int64(data.count)
        }
        lock.unlock()
        if let (start, data) = hit {
            let index = Int(offset - start)
            let count = min(want, min(data.count - index, Int(end - offset + 1)))
            if count > 0 {
                return data.subdata(in: index..<(index + count))
            }
        }

        if !window.contains(offset) {
            // Refill forward from the read position. Bounded by the stream's
            // own length and by the range this response promised.
            // Sequential continuation grows the window; a jump resets it.
            let sequential = offset == window.end && window.end != 0
            window.size = sequential
                ? min(window.size * 2, Self.maxWindow)
                : Self.minWindow
            let fetchEnd = min(offset + window.size - 1, stream.contentLength - 1)
            guard offset <= fetchEnd else {
                return Data()
            }
            guard let fresh = fetch(stream, from: offset, to: fetchEnd) else {
                return nil
            }
            lock.lock()
            window.start = offset
            window.data = fresh
            lock.unlock()
            AppLog.player(
                "loopback[\(id.suffix(2))]: window refilled at \(offset / 1024) KB,"
                    + " \(fresh.count / 1024) KB held"
            )
        }

        lock.lock()
        let available = window.contains(offset)
            ? window.slice(from: offset, max: min(want, Int(end - offset + 1)))
            : Data()
        lock.unlock()
        return available
    }

    /// Blocking ranged fetch from googlevideo. Runs on a connection's own
    /// queue, never the main thread.
    private func fetch(_ stream: Stream, from start: Int64, to end: Int64) -> Data? {
        var request = URLRequest(url: stream.url)
        // URLCache keys on the URL and ignores Range, so a cached reply would be
        // replayed for every range. Measured: every request came back with the
        // first response's two bytes.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for (key, value) in stream.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                result = data
            } else {
                AppLog.player("loopback: upstream HTTP \(status) for \(start)-\(end)")
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return result
    }

    // MARK: - Socket helpers

    private func readRequest(_ client: Int32) -> (String, String?, Bool)? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var text = ""
        while !text.contains("\r\n\r\n") {
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else {
                return nil
            }
            text += String(decoding: buffer[0..<n], as: UTF8.self)
            if text.count > 16_384 {
                return nil
            }
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return nil
        }
        let isHead = parts[0].uppercased() == "HEAD"
        let path = String(parts[1].drop { $0 == "/" })
        let range = lines.first { $0.lowercased().hasPrefix("range:") }
            .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }
        return (path, range, isHead)
    }

    /// `bytes=START-END`, `bytes=START-`, or `bytes=-SUFFIX`.
    static func parseRange(_ header: String, total: Int64) -> (Int64, Int64)? {
        guard let spec = header.components(separatedBy: "=").last else {
            return nil
        }
        let bounds = spec.components(separatedBy: "-")
        guard bounds.count == 2 else {
            return nil
        }
        let first = bounds[0].trimmingCharacters(in: .whitespaces)
        let second = bounds[1].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            guard let suffix = Int64(second), suffix > 0 else {
                return nil
            }
            return (max(0, total - suffix), total - 1)
        }
        guard let start = Int64(first) else {
            return nil
        }
        let end = Int64(second) ?? (total - 1)
        return (start, min(end, total - 1))
    }

    private func send(_ client: Int32, _ text: String) -> Bool {
        sendBody(client, Data(text.utf8))
    }

    private func sendBody(_ client: Int32, _ data: Data) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else {
                return true
            }
            while sent < data.count {
                let n = write(client, base + sent, data.count - sent)
                if n <= 0 {
                    return false
                }
                sent += n
            }
            return true
        }
    }
}
