import Foundation

enum DirectPlaybackClient: Equatable, CustomStringConvertible {
    case androidVR
    /// Vision Pro's client: anonymous like android_vr, but the only one whose
    /// SABR session is still served past the first minute of a video.
    case visionOS
    case web
    case mweb
    /// The living-room client. The only one our device-code OAuth token is
    /// accepted by, and SABR-only: its formats carry no `url`.
    case tv

    var description: String {
        clientName
    }

    var clientName: String {
        switch self {
        case .androidVR:
            "ANDROID_VR"
        case .visionOS:
            "VISIONOS"
        case .web:
            "WEB"
        case .mweb:
            "MWEB"
        case .tv:
            "TVHTML5"
        }
    }

    var clientVersion: String {
        switch self {
        case .androidVR:
            "1.65.10"
        case .visionOS:
            "1.02"
        case .web:
            "2.20231121.08.00"
        case .mweb:
            "2.20250101.00.00"
        case .tv:
            // Whatever `youtube.com/tv` is running, scraped beside the player
            // path. It was pinned to 5.20260707 while that version still handed
            // out stream URLs; since 2026-08 it answers SABR-only like 7.x, so
            // the pin bought nothing and left `cver` naming a client YouTube no
            // longer serves — which googlevideo answers with 403.
            SignatureTimestampService.tvClientVersion ?? "7.20260816.19.00"
        }
    }

    var clientHeaderName: String {
        switch self {
        case .androidVR:
            "28"
        case .visionOS:
            "101"
        case .web:
            "1"
        case .mweb:
            "2"
        case .tv:
            "7"
        }
    }

    var userAgent: String {
        switch self {
        case .androidVR:
            "com.google.android.apps.youtube.vr.oculus/"
                + "1.65.10 (Linux; U; Android 12L;"
                + " eureka-user Build/SQ3A.220605.009.A1) gzip"
        case .web:
            UserAgent.chromeMac
        case .visionOS:
            UserAgent.visionOS
        case .mweb:
            UserAgent.mobileSafari
        case .tv:
            UserAgent.webOSTV
        }
    }

    /// Whether this client uses cookie-based auth instead of OAuth Bearer token
    var usesCookieAuth: Bool {
        switch self {
        case .androidVR, .visionOS, .mweb:
            true
        // The TV client authenticates with the OAuth Bearer, like WEB.
        case .web, .tv:
            false
        }
    }

    /// Whether the /player body needs contentCheckOk / racyCheckOk / playbackContext flags
    var requiresContentCheckFlags: Bool {
        true
    }

    /// MWEB playback is anonymous and its GVS pot binds to the video id; sending
    /// the app's authenticated (TV device) session cookies makes YouTube return a
    /// session-bound URL the anonymous pot can't satisfy (403). Keep it cookieless.
    ///
    /// TV is cookieless for the same reason, the other way round: it authenticates
    /// with the OAuth Bearer, and the cookies in the shared jar belong to whatever
    /// else has been on the wire. The same body, timestamp, token and user agent
    /// sent from a shell with no cookies mints a URL googlevideo serves, while the
    /// app's mint comes back marked `pcm2cms=yes` and is refused (measured
    /// 2026-08-18, same account, same public IP).
    var sendsCookies: Bool {
        switch self {
        // visionOS plays anonymously; the jar holds whatever else has been on
        // the wire, and a session-bound URL is not what this client asks for.
        case .mweb, .tv, .visionOS:
            false
        case .androidVR, .web:
            true
        }
    }

    var context: [String: Any] {
        switch self {
        case .androidVR:
            InnertubeContexts.androidVR
        case .visionOS:
            InnertubeContexts.visionOS
        case .web:
            InnertubeContexts.web
        case .mweb:
            InnertubeContexts.mweb
        case .tv:
            InnertubeContexts.tv
        }
    }

    var playerURLSuffix: String {
        switch self {
        case .androidVR, .visionOS, .mweb:
            "?prettyPrint=false"
        case .web, .tv:
            ""
        }
    }

    /// Normalises a signed media URL for direct playback: replaces `pot`/`cver`
    /// query params with this client's values (the segment CDN requires a
    /// matching client version, plus `pot` when a token is available).
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
        items.append(URLQueryItem(name: "cver", value: clientVersion))
        components.queryItems = items
        return components.url ?? baseURL
    }

    /// Build HTTP headers for stream requests (AVPlayer asset loading, direct URL fetches)
    func streamHeaders(visitorData: String?) -> [String: String] {
        var headers: [String: String] = [
            HTTPHeader.accept: "*/*",
            HTTPHeader.acceptLanguage: "*",
            HTTPHeader.userAgent: userAgent,
            HTTPHeader.xYoutubeClientName: clientHeaderName,
            HTTPHeader.xYoutubeClientVersion: clientVersion
        ]
        switch self {
        case .web:
            headers[HTTPHeader.referer] = AppURLs.YouTube.base + "/"
            headers[HTTPHeader.origin] = AppURLs.YouTube.base
            headers[HTTPHeader.xOrigin] = AppURLs.YouTube.base
        case .androidVR, .visionOS, .mweb, .tv:
            break
        }
        if let visitorData, !visitorData.isEmpty {
            headers[HTTPHeader.xGoogVisitorId] = visitorData
        }
        return headers
    }

    /// Build HTTP headers for /player API requests
    func apiHeaders(token: String, visitorData: String?) -> [String: String] {
        var headers: [String: String] = [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON]
        if !usesCookieAuth {
            headers[HTTPHeader.authorization] = "Bearer \(token)"
        }
        headers[HTTPHeader.xYoutubeClientName] = clientHeaderName
        headers[HTTPHeader.xYoutubeClientVersion] = clientVersion
        headers[HTTPHeader.userAgent] = userAgent
        switch self {
        case .web:
            break
        case .tv:
            headers[HTTPHeader.referer] = AppURLs.YouTube.base + "/tv"
        case .androidVR, .visionOS, .mweb:
            if let visitorData, !visitorData.isEmpty {
                headers[HTTPHeader.xGoogVisitorId] = visitorData
            }
        }
        if case .androidVR = self {
            headers[HTTPHeader.origin] = AppURLs.YouTube.base
        }
        return headers
    }
}
