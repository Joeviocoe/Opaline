import Foundation

/// Mints a GVS proof-of-origin (`pot`) token bound to a content id.
protocol PoTokenProvider: AnyObject {
    /// - Parameter identifier: the content binding. For the mweb client this is
    ///   the VIDEO ID (YouTube's current experiment binds the pot to the video,
    ///   not visitorData).
    func fetchSessionToken(
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    )

    /// Drops any cached token for the binding — the next fetch mints fresh.
    /// Call when YouTube rejects a previously working token (bot-check).
    func invalidateToken(identifier: String)
}

/// Fetches the `pot` from a remote bgutil-ytdlp-pot-provider over HTTP. Replaces
/// the on-device WKWebView BotGuard mint, whose tokens GVS rejected even when
/// correctly video-id-bound (the reference BgUtils tokens were accepted).
final class RemotePoTokenService: PoTokenProvider {
    enum ProviderError: Error {
        case notConfigured
        case badResponse
    }

    private struct CachedMint {
        let token: String
        let minted: Date
    }

    static let shared = RemotePoTokenService()
    /// GVS rejected a 50-minute-old token in the field, so cached mints go
    /// stale well before the provider's own multi-hour cache window.
    private static let tokenTTL: TimeInterval = 30 * 60

    private let transport: HTTPTransport
    private var cache: [String: CachedMint] = [:]
    /// Bindings whose next mint must skip the remote provider's server-side
    /// cache too — set by `invalidateToken`.
    private var bypassProviderCache: Set<String> = []
    private let lock = NSLock()

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    func fetchSessionToken(
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if let cached = cachedToken(for: identifier) {
            AppLog.poToken("cache hit for \(identifier)")
            completion(.success(cached))
            return
        }
        guard let endpoint = AppURLs.PoTokenProvider.endpoint,
              let body = try? JSONSerialization.data(
                  withJSONObject: requestPayload(identifier: identifier)
              ) else {
            completion(.failure(ProviderError.notConfigured))
            return
        }
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON],
            body: body,
            timeout: 15
        )
        AppLog.poToken("requesting pot for \(identifier) via \(endpoint.host ?? "")")
        transport.send(request, cancellationToken: nil) { [weak self] result in
            self?.handle(result: result, identifier: identifier, completion: completion)
        }
    }

    private func handle(
        result: Result<HTTPResponse, Error>,
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            AppLog.poToken("pot request failed: \(error.localizedDescription)")
            completion(.failure(error))
        case .success(let response):
            guard let token = parseToken(response.data), !token.isEmpty else {
                AppLog.poToken("pot response missing poToken (status \(response.status))")
                completion(.failure(ProviderError.badResponse))
                return
            }
            AppLog.poToken(
                "got pot for \(identifier) len=\(token.count) tail=\(token.suffix(4))"
            )
            storeToken(token, for: identifier)
            completion(.success(token))
        }
    }

    private func parseToken(_ data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["poToken"] ?? json?["po_token"]) as? String
    }

    func invalidateToken(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[identifier] = nil
        bypassProviderCache.insert(identifier)
    }

    /// `bypass_cache` asks the bgutil provider to re-mint instead of serving
    /// its own cached token (which is what just got rejected); providers that
    /// predate the flag simply ignore it.
    private func requestPayload(identifier: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var payload: [String: Any] = ["content_binding": identifier]
        if bypassProviderCache.remove(identifier) != nil {
            payload["bypass_cache"] = true
        }
        return payload
    }

    private func cachedToken(for identifier: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[identifier],
              Date().timeIntervalSince(entry.minted) < Self.tokenTTL else {
            return nil
        }
        return entry.token
    }

    private func storeToken(_ token: String, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[identifier] = CachedMint(token: token, minted: Date())
    }
}
