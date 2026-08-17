import Foundation

/// Mints a GVS proof-of-origin (`pot`) token bound to a content id.
protocol PoTokenProvider: AnyObject {
    /// - Parameter identifier: the content binding. For the mweb client this is
    ///   the VIDEO ID (YouTube's current experiment binds the pot to the video,
    ///   not visitorData).
    /// - Parameter client: which client's attestation the token must carry.
    ///   The stream server checks it against the client that minted the
    ///   playback URL, so a WEB token is refused on a television's stream.
    func fetchSessionToken(
        identifier: String,
        client: String,
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
    /// Callers waiting on a mint that is already on the wire, keyed the same
    /// way as the cache. One binding is one request no matter how many videos
    /// ask at once — a cold provider used to be asked three times over while
    /// its first answer was still coming, and all three timed out.
    private var inFlight: [String: [(Result<String, Error>) -> Void]] = [:]
    private let lock = NSLock()

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    /// - Parameter client: which client's attestation the token must carry.
    ///   The stream server checks it against the client that minted the
    ///   playback URL, so a WEB token is refused on a television's stream.
    func fetchSessionToken(
        identifier: String,
        client: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let key = "\(client)|\(identifier)"
        if let cached = cachedToken(for: key) {
            AppLog.poToken("cache hit for \(key)")
            completion(.success(cached))
            return
        }
        guard let endpoint = AppURLs.PoTokenProvider.endpoint else {
            completion(.failure(ProviderError.notConfigured))
            return
        }
        // Joins an existing mint rather than starting a second one. Checked
        // before the payload is built: `requestPayload` consumes the
        // bypass-cache flag, and a waiter must not eat it.
        guard startMint(key: key, waiter: completion) else {
            AppLog.poToken("mint already in flight for \(key)")
            return
        }
        guard let request = mintRequest(
            endpoint: endpoint, identifier: identifier, client: client
        ) else {
            finishMint(key: key, result: .failure(ProviderError.notConfigured))
            return
        }
        AppLog.poToken("requesting pot for \(identifier) via \(endpoint.host ?? "")")
        transport.send(request, cancellationToken: nil) { [weak self] result in
            self?.handle(result: result, identifier: key)
        }
    }

    private func mintRequest(
        endpoint: URL, identifier: String, client: String
    ) -> HTTPRequest? {
        guard let body = try? JSONSerialization.data(
            withJSONObject: requestPayload(identifier: identifier, client: client)
        ) else {
            return nil
        }
        return HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON],
            body: body,
            timeout: 15,
            isPlayback: true
        )
    }

    private func handle(
        result: Result<HTTPResponse, Error>,
        identifier: String
    ) {
        switch result {
        case .failure(let error):
            AppLog.poToken("pot request failed: \(error.localizedDescription)")
            finishMint(key: identifier, result: .failure(error))
        case .success(let response):
            guard let token = parseToken(response.data), !token.isEmpty else {
                AppLog.poToken("pot response missing poToken (status \(response.status))")
                finishMint(key: identifier, result: .failure(ProviderError.badResponse))
                return
            }
            AppLog.poToken(
                "got pot for \(identifier) len=\(token.count) tail=\(token.suffix(4))"
            )
            storeToken(token, for: identifier)
            finishMint(key: identifier, result: .success(token))
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
    private func requestPayload(identifier: String, client: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var payload: [String: Any] = ["content_binding": identifier, "client": client]
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

    /// Registers a waiter. `true` means this caller owns the mint and must
    /// send the request; `false` means one is already on the wire.
    private func startMint(
        key: String, waiter: @escaping (Result<String, Error>) -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight[key] == nil else {
            inFlight[key]?.append(waiter)
            return false
        }
        inFlight[key] = [waiter]
        return true
    }

    /// Answers everyone who waited on this binding. Called off the lock so a
    /// waiter is free to ask for another token from its own callback.
    private func finishMint(key: String, result: Result<String, Error>) {
        lock.lock()
        let waiters = inFlight.removeValue(forKey: key) ?? []
        lock.unlock()
        waiters.forEach { $0(result) }
    }
}
