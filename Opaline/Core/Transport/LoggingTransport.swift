import Foundation

/// Transport decorator that logs each request's method, host+path and outcome.
/// Composes around any inner `HTTPTransport` (chain-of-responsibility).
final class LoggingTransport: HTTPTransport {
    /// Sequence number across the whole run, printed with every line: the
    /// count at any point in the log is how many requests the app has made
    /// to get there, which is what makes two runs comparable.
    private static var counter = 0
    private static let counterLock = NSLock()

    private let wrapped: HTTPTransport

    init(_ wrapped: HTTPTransport) {
        self.wrapped = wrapped
    }

    private static func nextSequenceNumber() -> Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        counter += 1
        return counter
    }

    private static func label(for request: HTTPRequest) -> String {
        "#\(nextSequenceNumber()) \(request.method.rawValue) "
            + "\(request.url.host ?? "")\(request.url.path)"
    }

    private static func log(_ label: String, _ result: Result<HTTPResponse, Error>) {
        switch result {
        case .success(let response):
            AppLog.log("Transport", "\(label) -> \(response.status)")
        case .failure(let error):
            AppLog.log("Transport", "\(label) -> \(error)")
        }
    }

    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        let label = Self.label(for: request)
        wrapped.send(request, cancellationToken: cancellationToken) { result in
            Self.log(label, result)
            completion(result)
        }
    }

    func stream(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        onChunk: @escaping (Data) -> Bool,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        let label = Self.label(for: request)
        wrapped.stream(
            request, cancellationToken: cancellationToken, onChunk: onChunk
        ) { result in
            Self.log(label, result)
            completion(result)
        }
    }
}
