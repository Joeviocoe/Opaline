import AVFoundation
import Foundation

/// Delivers playback over SABR (`serverAbrStreamingUrl` + UMP) instead of the
/// legacy `adaptiveFormats` URLs.
///
/// Those URLs stop serving about a minute after they are minted unless the
/// visitor identity happens to be a clean one, which is what
/// `PlaybackFacade+Identity` works around by re-drawing identities until one
/// passes. SABR needs none of that: identities the legacy probe rejects with
/// 403 stream over SABR without complaint (measured 2026-08-14, including an
/// identity burned down on purpose), so playback starts immediately with no
/// probe and no re-draws.
///
/// The bytes are fMP4 laid out exactly like the file behind the legacy URL —
/// the init segment carries `moov` and `sidx`, and `MEDIA_HEADER.start_range`
/// is an offset into that same file — so AVPlayer's byte-range reads map
/// straight onto the session. It reaches AVPlayer through a loopback HTTP
/// server rather than a resource loader; see `SABRDelivery+Serving`.
final class SABRDelivery: StreamDelivery {
    /// One stream as the serving layer sees it: the format, its segment index
    /// from `sidx`, and the path it is served under.
    struct Track {
        let format: DashFormatInfo
        let segments: [SidxSegment]
        let path: String
    }

    let label = "sabr"

    private let transport: HTTPTransport
    private var session: SABRSession?
    /// One server for the whole delivery; sessions come and go behind it.
    var server: LocalMediaServer?
    var serverBase: URL?
    /// Bumped per session so each one gets fresh playlist URLs.
    var generation = 0
    /// Where the next attached item should start, set by a quality switch.
    var pendingStartAt: Double?

    /// What the server routes to right now.
    ///
    /// Written when playback is built and read by the server on its own queue,
    /// so every access takes the lock. An unsynchronised struct holding an
    /// array is exactly the kind of data race that corrupts memory and then
    /// crashes somewhere unrelated.
    private var storedRoute: Route?
    private let routeLock = NSLock()

    var route: Route? {
        get {
            routeLock.lock()
            defer { routeLock.unlock() }
            return storedRoute
        }
        set {
            routeLock.lock()
            storedRoute = newValue
            routeLock.unlock()
        }
    }

    init(transport: HTTPTransport) {
        self.transport = transport
    }

    /// `videoPlaybackUstreamerConfig` arrives web-safe base64 and unpadded.
    static func decodeConfig(_ value: String) -> Data? {
        var text = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        return Data(base64Encoded: text)
    }

    static func formatInfo(_ format: DashFormatInfo) -> SabrFormatInfo {
        // `xtags` is required whenever the format has one — without it the
        // server answers with policy and no media. An itag alone only works
        // for videos with a single audio track, which is what made an earlier
        // spike say it was optional.
        SabrFormatInfo(
            itag: format.itag,
            lastModified: nil,
            xtags: format.xtags,
            audioTrackId: format.audioTrackId,
            isDrc: false,
            mimeType: format.mimeType,
            bitrate: format.bitrate,
            width: format.width,
            height: format.height
        )
    }

    /// Whether a response can be played this way at all.
    static func canServe(_ info: DirectPlaybackInfo) -> Bool {
        info.serverAbrStreamingURL != nil && info.videoPlaybackUstreamerConfig != nil
    }

    func prepare(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let url = request.info.serverAbrStreamingURL,
              let configString = request.info.videoPlaybackUstreamerConfig,
              let config = Self.decodeConfig(configString) else {
            completion(.failure(SABRError.server("player response carries no SABR stream")))
            return
        }
        let playhead = request.resumeAt.map { Int($0 * 1_000) }
            ?? route?.session.lastServedMs ?? 0
        pendingStartAt = request.resumeAt.map { _ in Double(playhead) / 1_000 }
        let session = SABRSession(
            transport: transport,
            url: url,
            ustreamerConfig: config,
            audio: Self.formatInfo(request.audio),
            video: Self.formatInfo(request.video)
        )
        self.session = session
        PlaybackProgress.step("player.status.openingSABR")
        session.start(resumeAt: request.resumeAt == nil ? 0 : playhead) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let inits):
                self?.buildPlayback(request, session: session, inits: inits, completion: completion)
            }
        }
    }

    /// Playback moving elsewhere drops this delivery; the loopback server has
    /// to go with it rather than linger until collection.
    deinit {
        server?.stop()
    }
}
