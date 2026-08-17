import Foundation

/// Transport decorator owning the auth cross-cut: when the inner transport
/// reports `401 Unauthorized`, it kicks off an OAuth token refresh so the next
/// request carries a fresh Bearer. This keeps `URLSessionTransport` free of any
/// `OAuthClient` coupling.
///
/// (Automatic same-request retry-after-refresh is intentionally deferred — call
/// sites still fetch a valid token up front via `OAuthClient.validToken`.)
final class AuthorizingTransport: HTTPTransport {
    private let wrapped: HTTPTransport

    init(_ wrapped: HTTPTransport) {
        self.wrapped = wrapped
    }

    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        wrapped.send(request, cancellationToken: cancellationToken) { result in
            completion(self.noticing401(result))
        }
    }

    func stream(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        onChunk: @escaping (Data) -> Bool,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        wrapped.stream(
            request, cancellationToken: cancellationToken, onChunk: onChunk
        ) { result in
            completion(self.noticing401(result))
        }
    }

    private func noticing401(
        _ result: Result<HTTPResponse, Error>
    ) -> Result<HTTPResponse, Error> {
        if case .success(let response) = result, response.status == 401 {
            OAuthClient.shared.tryRefreshIfNeeded()
        }
        return result
    }
}
