import Foundation
import Network
import QuartzCore

/// A minimal HTTP/1.1 server on the loopback interface, used to hand SABR media
/// to AVPlayer.
///
/// AVPlayer will not take HLS segments from a resource loader — a custom scheme
/// there must answer with a redirect to a real URL (-12881), and SABR segments
/// have no URL of their own. Serving them over `127.0.0.1` is the adapter
/// between a protocol that pushes bytes and a player that insists on fetching
/// them.
///
/// Keeps connections alive between requests. CFNetwork reuses sockets and
/// ignores `Connection: close`, so closing after each response left the player
/// reaching for a socket that was already gone — reported as -1005, "the
/// network connection was lost". It also answers HEAD and Range, which AVPlayer
/// probes with; leaving those unanswered surfaces as a failed player item.
final class LocalMediaServer {
    /// Answers a path with a body and content type, or nil for 404. Called on
    /// the server's queue; the completion may be called later, from anywhere.
    typealias Handler = (
        _ path: String,
        _ completion: @escaping (Data?, String) -> Void
    ) -> Void

    /// One parsed request — everything this server acts on.
    struct Request {
        let method: String
        let path: String
        /// Start and optional end, when the client asked for a byte range.
        let range: (start: Int, end: Int?)?
    }

    private let listener: NWListener
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.ytvlite.local-media-server")

    /// The port the listener settled on, once it is ready.
    private(set) var port: UInt16?

    init?(handler: @escaping Handler) {
        let parameters = NWParameters.tcp
        // Loopback only: this must never be reachable from the network.
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else {
            AppLog.hls("local server: could not create listener")
            return nil
        }
        self.listener = listener
        self.handler = handler
    }

    /// Parses the request head once it has fully arrived.
    static func parseRequest(in buffer: Data) -> Request? {
        guard let text = String(data: buffer, encoding: .utf8),
              text.contains("\r\n\r\n") else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else {
            return nil
        }
        let range = lines
            .first { $0.lowercased().hasPrefix("range:") }
            .flatMap(byteRange(in:))
        return Request(method: String(parts[0]), path: String(parts[1]), range: range)
    }

    /// `Range: bytes=start-end`, where the end may be absent.
    static func byteRange(in header: String) -> (start: Int, end: Int?)? {
        guard let spec = header.split(separator: "=").last else {
            return nil
        }
        let bounds = spec
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "-", omittingEmptySubsequences: false)
        guard let start = Int(bounds.first ?? "") else {
            return nil
        }
        return (start, bounds.count > 1 ? Int(bounds[1]) : nil)
    }

    /// Builds the response, honouring HEAD (headers only) and Range (206).
    /// Head and body separately — concatenating them copied every segment,
    /// which on a 3MB video segment is a visible memory spike.
    static func response(
        for request: Request,
        body: Data?,
        contentType: String
    ) -> (head: Data, body: Data) {
        guard let body else {
            AppLog.hls("local server: 404 \(request.path)")
            return (Data(
                "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n".utf8
            ), Data())
        }
        var slice = body
        var status = "200 OK"
        var extra = ""
        if let range = request.range, range.start < body.count {
            let last = min(range.end ?? body.count - 1, body.count - 1)
            slice = body.slice(from: range.start, length: last + 1 - range.start) ?? body
            status = "206 Partial Content"
            extra = "Content-Range: bytes \(range.start)-\(last)/\(body.count)\r\n"
        }
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(slice.count)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += extra
        head += "Connection: keep-alive\r\n\r\n"
        return request.method == "HEAD" ? (Data(head.utf8), Data()) : (Data(head.utf8), slice)
    }

    /// Starts listening and calls back with the base URL once the port is known.
    func start(completion: @escaping (URL?) -> Void) {
        var reported = false
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !reported else {
                return
            }
            switch state {
            case .ready:
                reported = true
                self.port = self.listener.port?.rawValue
                let url = self.listener.port.flatMap {
                    URL(string: "http://127.0.0.1:\($0.rawValue)")
                }
                AppLog.hls("local server ready on \(url?.absoluteString ?? "?")")
                completion(url)
            case .failed(let error):
                reported = true
                AppLog.hls("local server failed: \(error.localizedDescription)")
                completion(nil)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        // Keep-alive means the player decides when a connection is done, so
        // its end has to be noticed and the socket released — otherwise they
        // pile up in CLOSE_WAIT for the whole session.
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    /// Reads until the end of the request head. No bodies: these are all GETs
    /// and HEADs.
    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 8 * 1_024
        ) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                return
            }
            var buffer = buffer
            if let chunk {
                buffer.append(chunk)
            }
            if let request = Self.parseRequest(in: buffer) {
                self.respond(to: request, on: connection)
                return
            }
            // isComplete here is the peer half-closing: nothing more is
            // coming, so let the socket go instead of waiting on it.
            guard error == nil, !isComplete, buffer.count < 8 * 1_024 else {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: buffer)
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let started = CACurrentMediaTime()
        handler(request.path) { body, contentType in
            let elapsed = (CACurrentMediaTime() - started) * 1_000
            let size = body?.count ?? -1
            let label = "\(request.method) \(request.path)"
            AppLog.hls(String(format: "serve %@ -> %d bytes in %.0f ms", label, size, elapsed))
            let response = Self.response(for: request, body: body, contentType: contentType)
            let body = response.body
            connection.send(
                content: response.head,
                completion: .contentProcessed { [weak self] _ in
                    guard !body.isEmpty else {
                        self?.receiveRequest(on: connection, buffer: Data())
                        return
                    }
                    connection.send(content: body, completion: .contentProcessed { _ in
                        // Stay open and wait for the next request rather than
                        // closing: the player expects to reuse this socket.
                        self?.receiveRequest(on: connection, buffer: Data())
                    })
                }
            )
        }
    }

    deinit {
        listener.cancel()
    }
}
