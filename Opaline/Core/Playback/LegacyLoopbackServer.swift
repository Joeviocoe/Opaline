import Darwin
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

    /// Bytes fetched upstream per request. Under googlevideo's ~1 MiB throttle
    /// window; the client never sees the seams.
    private static let upstreamChunk: Int64 = 900_000

    private var streams: [String: Stream] = [:]
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
        lock.unlock()
        return URL(string: "http://127.0.0.1:\(port)/\(id)")
    }

    func withdraw(_ id: String) {
        lock.lock()
        streams.removeValue(forKey: id)
        lock.unlock()
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

    private func serve(_ client: Int32) {
        guard let request = readRequest(client) else {
            return
        }
        let (path, rangeHeader, isHead) = request
        lock.lock()
        let stream = streams[path]
        lock.unlock()
        guard let stream = stream else {
            _ = send(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            return
        }

        let total = stream.contentLength
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
        while offset <= end {
            let chunkEnd = min(offset + Self.upstreamChunk - 1, end)
            guard let data = fetch(stream, from: offset, to: chunkEnd) else {
                return
            }
            guard sendBody(client, data) else {
                return
            }
            offset += Int64(data.count)
            if data.isEmpty {
                return
            }
        }
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
