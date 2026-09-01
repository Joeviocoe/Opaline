import Foundation

// MARK: - Request parsing and response building
//
// The HTTP wire format, kept apart from the connection handling.

extension LocalMediaServer {
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
        guard let body = body else {
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
}
