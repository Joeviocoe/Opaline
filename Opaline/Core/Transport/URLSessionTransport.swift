import Foundation

/// The single `URLSession`-backed transport — the only place in the app that
/// touches `URLSession` (aside from `HLSPlaybackBuilder`'s AVFoundation byte
/// streaming, which is documented). Maps status codes onto `APIError` and
/// honours `CancellationToken`: a cancelled task silences its callback,
/// matching the previous `APIClient` behaviour.
final class URLSessionTransport: HTTPTransport {
    /// Where response handling lands, off URLSession's serial delegate queue.
    /// Two lanes rather than one: parsing is the expensive half of a request
    /// and the playback plane must not wait behind a feed page for a core.
    private static let completionQueue = DispatchQueue(
        label: "com.ytvlite.transport.completion",
        qos: .default,
        attributes: .concurrent
    )
    private static let playbackQueue = DispatchQueue(
        label: "com.ytvlite.transport.playback",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// The delegate-backed session behind `stream`, built on first use.
    private let streaming = StreamingSession()
    private let session: URLSession
    /// A session with no cookie storage — used for requests that opt out of
    /// cookies (`sendsCookies == false`). Guarantees the shared jar is never
    /// attached, independent of the per-request `httpShouldHandleCookies` flag.
    private let cookielessSession: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.cookielessSession = URLSession(configuration: config)
    }

    static func isCancelled(_ error: Error?) -> Bool {
        (error as NSError?)?.code == NSURLErrorCancelled
    }

    /// The transport reports transport-level failures only; interpreting the
    /// HTTP status is the caller's concern (some want 4xx as an error, others —
    /// e.g. SponsorBlock's 404 — treat it as a valid empty result).
    static func map(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<HTTPResponse, Error> {
        if let error = error {
            return .failure(APIError.transport(error))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(APIError.invalidResponse)
        }
        return .success(
            HTTPResponse(
                status: http.statusCode,
                headers: stringHeaders(http.allHeaderFields),
                data: data ?? Data()
            )
        )
    }

    static func stringHeaders(
        _ raw: [AnyHashable: Any]
    ) -> [String: String] {
        raw.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
    }

    func stream(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        onChunk: @escaping (Data) -> Bool,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        streaming.start(
            urlRequest(for: request),
            cancellationToken: cancellationToken,
            onChunk: onChunk,
            completion: completion
        )
    }

    private func urlRequest(for request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = request.sendsCookies
        if let timeout = request.timeout {
            urlRequest.timeoutInterval = timeout
        }
        request.headers.forEach {
            urlRequest.setValue($1, forHTTPHeaderField: $0)
        }
        return urlRequest
    }

    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = request.sendsCookies
        if let timeout = request.timeout {
            urlRequest.timeoutInterval = timeout
        }
        request.headers.forEach {
            urlRequest.setValue($1, forHTTPHeaderField: $0)
        }
        // Route cookie-opted-out requests through a jar-less session so the
        // shared cookies can't leak in regardless of httpShouldHandleCookies.
        let session = request.sendsCookies ? self.session : cookielessSession
        let queue = request.isPlayback ? Self.playbackQueue : Self.completionQueue
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if Self.isCancelled(error) {
                return
            }
            let mapped = Self.map(data: data, response: response, error: error)
            // URLSession hands every response to one serial delegate queue, so
            // a slow completion holds up all the others behind it: parsing a
            // MrBeast /next takes 3 s on an A7, and the dub probe racing the
            // player load waits them out for nothing. Callers already ran off
            // the main thread — they now also run off each other.
            queue.async { completion(mapped) }
        }
        task.priority = request.isPlayback
            ? URLSessionTask.highPriority
            : URLSessionTask.defaultPriority
        cancellationToken?.register(task)
        task.resume()
    }
}
