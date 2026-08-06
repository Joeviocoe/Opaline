import Foundation

/// Transport decorator that logs each request's method, host+path and outcome.
/// Composes around any inner `HTTPTransport` (chain-of-responsibility).
final class LoggingTransport: HTTPTransport {
    private let wrapped: HTTPTransport

    init(_ wrapped: HTTPTransport) {
        self.wrapped = wrapped
    }

    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        let label = "\(request.method.rawValue) "
            + "\(request.url.host ?? "")\(request.url.path)"
        wrapped.send(request, cancellationToken: cancellationToken) { result in
            switch result {
            case .success(let response):
                AppLog.log("Transport", "\(label) -> \(response.status)")
            case .failure(let error):
                AppLog.log("Transport", "\(label) -> \(error)")
            }
            completion(result)
        }
    }
}
