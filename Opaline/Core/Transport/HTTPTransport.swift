import Foundation

// MARK: - Transport model

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

struct HTTPRequest {
    var method: HTTPMethod
    var url: URL
    var headers: [String: String]
    var body: Data?
    /// Per-request timeout; nil uses the session default.
    var timeout: TimeInterval?
    /// When false, the shared cookie storage is neither sent nor updated for
    /// this request — used to keep the anonymous MWEB playback flow from being
    /// contaminated by the app's authenticated (TV device) session cookies.
    var sendsCookies: Bool
    /// The playback plane: `/player`, the po token, the n solve and the SABR
    /// pump. These get the network's and the CPU's attention ahead of
    /// everything else, because a spinner is on screen while they run and a
    /// thumbnail or a comment page can wait a beat. On a dual-core A7 the
    /// contention is real: parsing one `/next` costs three seconds.
    var isPlayback: Bool

    init(
        method: HTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        sendsCookies: Bool = true,
        isPlayback: Bool = false
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.sendsCookies = sendsCookies
        self.isPlayback = isPlayback
    }
}

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let data: Data
}

/// The single abstraction over the HTTP transport. All networking flows through
/// a `HTTPTransport` so cross-cutting concerns (auth, logging, retry) compose as
/// decorators and the only `URLSession` user is `URLSessionTransport`.
///
/// Failures are reported as `APIError` (the app-wide error type). Cancellation
/// is honoured via `CancellationToken`; a cancelled request never calls back.
protocol HTTPTransport: AnyObject {
    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    )

    /// Same, but hands the body over as it arrives.
    ///
    /// For a response that is one media segment this is an optimisation. For
    /// SABR, where a single response carries ten megabytes and several
    /// segments, it is the difference between working and not: waiting for the
    /// last byte before looking at the first one made the player wait five to
    /// sixteen seconds for a segment whose bytes had arrived seconds earlier.
    ///
    /// `onChunk` runs on the delivering queue, in order, and returns whether
    /// the caller wants more: returning false stops the transfer there and
    /// completes normally. A SABR response carries the segment that was asked
    /// for and then keeps going with several more; reading past the one that
    /// was wanted is megabytes of pure waste.
    ///
    /// The completion still reports the status, with an empty `data` —
    /// everything was handed over as it arrived.
    func stream(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        onChunk: @escaping (Data) -> Bool,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    )
}

extension HTTPTransport {
    /// The fallback for transports that do not stream: one chunk, at the end.
    func stream(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        onChunk: @escaping (Data) -> Bool,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        send(request, cancellationToken: cancellationToken) { result in
            if case .success(let response) = result {
                _ = onChunk(response.data)
            }
            completion(result)
        }
    }
}
