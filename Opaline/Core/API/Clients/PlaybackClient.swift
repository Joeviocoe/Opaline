import Foundation

/// What the player looks like to the server for one request.
struct SABRPlayerState {
    /// Which track a request is for. googlevideo's own adapter narrows every
    /// request this way; asking for both lets the server answer with whichever
    /// audio it likes, which is the default dub.
    enum Track {
        case audio
        case video
        case both

        /// `enabledTrackTypesBitfield`.
        var bitfield: Int {
            switch self {
            case .both:
                return 0
            case .audio:
                return 1
            case .video:
                return 2
            }
        }
    }

    let video: SabrFormatInfo
    /// The track playback is on, `nil` for single-audio videos.
    let audioTrackId: String?
    let wants: Track
    let playerMs: Int
}

/// How a client proves who it is.
enum PlaybackAuthorization {
    /// No credentials at all. What googlevideo throttles — see Opaline#76.
    case anonymous
    /// The device-code OAuth bearer. Only TVHTML5 accepts it on `/player`.
    case bearer
}

/// One YouTube client: where we go, how we go, and what we call ourselves.
///
/// Everything that separates one client from another lives in its own
/// implementation — version, user agent, headers, Innertube context and the
/// protobuf identity a SABR session sends. Adding a client is adding a file;
/// nothing else in the app learns its name.
protocol PlaybackClient {
    /// Innertube's own name for the client, e.g. `VISIONOS`.
    var name: String { get }
    var version: String { get }
    /// The `X-Youtube-Client-Name` number, e.g. `101`.
    var headerName: String { get }
    var userAgent: String { get }
    /// The `/player` endpoint this client posts to, suffix included.
    var playerURL: String { get }
    var innertubeContext: [String: Any] { get }
    var authorization: PlaybackAuthorization { get }
    /// Whether the shared cookie jar rides along. Anonymous clients keep it
    /// out: a session-bound URL is not what they can play.
    var sendsCookies: Bool { get }
    /// Whether this client's media URLs carry an `n` for the solver to answer.
    var needsSignatureSolver: Bool { get }
    /// Whether its `/player` lists dubbed audio tracks. Measured, not assumed:
    /// visionOS lists the same 22 tracks as ios and plays them anonymously
    /// (2026-08-18), so a dub no longer needs an account.
    var listsAudioTracks: Bool { get }
    /// What this client's session token binds to when the stream server makes
    /// it prove itself; `nil` for clients served without one.
    var attestationBinding: String? { get }

    /// The client's identity inside `streamerContext` — the server sizes and
    /// signs what it serves from this.
    func sabrClientInfo() -> Data
    /// `ClientAbrState`: what this client tells the server about the player —
    /// where it stands, which audio track it is on, and which track this
    /// request is for. Without the last two the server picks the default dub
    /// however the format ids are named.
    func sabrAbrState(_ state: SABRPlayerState) -> Data

    // Declared here, not only defaulted below: a client that overrides one of
    // these is called through the protocol, and only a requirement dispatches
    // dynamically.
    /// Anything this client adds to the `/player` body beyond the common
    /// shape — a television names itself there, the others say nothing.
    func decoratePlayerBody(_ body: inout [String: Any])
    func apiHeaders(token: String, visitorData: String?) -> [String: String]
    func streamHeaders(visitorData: String?) -> [String: String]
    func directURL(baseURL: URL, poToken: String?) -> URL
}

// MARK: - Shared behaviour

extension PlaybackClient {
    var needsSignatureSolver: Bool { false }
    var listsAudioTracks: Bool { false }
    var attestationBinding: String? { nil }

    func decoratePlayerBody(_ body: inout [String: Any]) {}

    /// Headers for `/player` calls.
    func apiHeaders(token: String, visitorData: String?) -> [String: String] {
        defaultAPIHeaders(token: token, visitorData: visitorData)
    }

    /// The shape every client starts from; overrides build on it.
    func defaultAPIHeaders(token: String, visitorData: String?) -> [String: String] {
        var headers = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.xYoutubeClientName: headerName,
            HTTPHeader.xYoutubeClientVersion: version,
            HTTPHeader.userAgent: userAgent
        ]
        switch authorization {
        case .bearer:
            headers[HTTPHeader.authorization] = "Bearer \(token)"
        case .anonymous:
            if let visitorData, !visitorData.isEmpty {
                headers[HTTPHeader.xGoogVisitorId] = visitorData
            }
        }
        return headers
    }

    /// Headers for media requests — AVPlayer asset loading and range fetches.
    func streamHeaders(visitorData: String?) -> [String: String] {
        var headers = [
            HTTPHeader.accept: "*/*",
            HTTPHeader.acceptLanguage: "*",
            HTTPHeader.userAgent: userAgent,
            HTTPHeader.xYoutubeClientName: headerName,
            HTTPHeader.xYoutubeClientVersion: version
        ]
        if let visitorData, !visitorData.isEmpty {
            headers[HTTPHeader.xGoogVisitorId] = visitorData
        }
        return headers
    }

    /// Points a signed media URL at this client: the CDN checks `cver` against
    /// the client that minted it, and takes `pot` when there is one.
    func directURL(baseURL: URL, poToken: String?) -> URL {
        guard var components = URLComponents(
            url: baseURL, resolvingAgainstBaseURL: false
        ) else {
            return baseURL
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "pot" || $0.name == "cver" }
        if let poToken, !poToken.isEmpty {
            items.append(URLQueryItem(name: "pot", value: poToken))
        }
        items.append(URLQueryItem(name: "cver", value: version))
        components.queryItems = items
        return components.url ?? baseURL
    }
}
