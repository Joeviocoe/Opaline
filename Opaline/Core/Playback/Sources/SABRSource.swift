import AVFoundation
import Foundation

/// Plays through SABR (`serverAbrStreamingUrl` + UMP) instead of the legacy
/// `adaptiveFormats` URLs.
///
/// Those URLs stop serving about a minute after they are minted unless the
/// visitor identity happens to be a clean one, which is what
/// `PlaybackFacade+Identity` works around by re-drawing identities until one
/// passes. SABR needs none of that: identities the legacy probe rejects with
/// 403 stream over SABR without complaint (measured 2026-08-14, including an
/// identity burned down on purpose). So playback starts immediately, with no
/// probe and no re-draws.
///
/// The bytes are still fMP4 laid out exactly like the file behind the legacy
/// URL — the init segment carries `moov` and `sidx`, and
/// `MEDIA_HEADER.start_range` is an offset into that same file — so AVPlayer's
/// byte-range reads map straight onto the session. Playback goes through a
/// a loopback HTTP server rather than a resource loader; see `SABRSource+Serving`.
final class SABRSource: VideoSource {
    /// What one resolved player response yields for a SABR session.
    struct Stream {
        let info: DirectPlaybackInfo
        let url: URL
        let config: Data
        let video: DashFormatInfo
        let audio: DashFormatInfo
    }

    /// One stream as the playlist layer sees it: the format, its segment index
    /// from `sidx`, and the path it is served under.
    struct Track {
        let format: DashFormatInfo
        let segments: [SidxSegment]
        let path: String

        var mediaPath: String { "media-\(path)" }
    }

    let kind: VideoSourceKind = .sabr
    var supportsQualitySelection: Bool { !availableQualities.isEmpty }
    private(set) var availableQualities: [VideoQuality] = []
    private(set) var currentQuality: VideoQuality?
    var currentCodecs: String? {
        AndroidVRSource.codecsLine(info: info, quality: currentQuality)
    }

    let transport: HTTPTransport
    private let apiClient: WatchService
    private var info: DirectPlaybackInfo?
    private var session: SABRSession?
    /// One server for the whole source; sessions come and go behind it.
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

    init(apiClient: WatchService, transport: HTTPTransport) {
        self.apiClient = apiClient
        self.transport = transport
    }

    // MARK: - Type methods

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

    /// The pieces a session needs, or nil when the response carries no SABR
    /// stream at all.
    static func stream(from info: DirectPlaybackInfo, video: DashFormatInfo) -> Stream? {
        guard let url = info.serverAbrStreamingURL,
              let configString = info.videoPlaybackUstreamerConfig,
              let config = decodeConfig(configString),
              let audio = info.dashAudioFormat else {
            return nil
        }
        return Stream(info: info, url: url, config: config, video: video, audio: audio)
    }

    // MARK: - VideoSource

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        apiClient.fetchDirectPlayback(
            videoId: videoId,
            client: .androidVR,
            poToken: nil,
            cancellationToken: cancellation
        ) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let info):
                self?.prepare(info: info, completion: completion)
            }
        }
    }

    /// Switches quality by restarting the session on the new format.
    ///
    /// SABR negotiates the format inside the request, so there is no playlist
    /// to swap — the session is rebuilt and the shell restores the position,
    /// exactly as the legacy source does it.
    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let info,
              let video = info.allDashVideoFormats.first(where: { "\($0.itag)" == quality.id }),
              let stream = Self.stream(from: info, video: video) else {
            completion(.failure(SABRError.server("no such quality")))
            return
        }
        // The shell's playhead, not the session's own estimate: the session
        // only knows which segment it last handed over, which lags where the
        // player actually stands.
        let playhead = resumeAt.map { Int($0 * 1_000) } ?? route?.session.lastServedMs ?? 0
        pendingStartAt = Double(playhead) / 1_000
        openAndStart(stream, resumeAt: playhead) { [weak self] result in
            // Only adopt the new quality if the switch actually produced
            // playback — otherwise the overlay claims a resolution that is not
            // playing, which is what made this look like it half-worked.
            if case .success = result {
                self?.currentQuality = quality
            }
            completion(result)
        }
    }

    // MARK: - Preparation

    private func openSession(_ stream: Stream) -> SABRSession {
        let session = SABRSession(
            transport: transport,
            url: stream.url,
            ustreamerConfig: stream.config,
            audio: Self.formatInfo(stream.audio),
            video: Self.formatInfo(stream.video)
        )
        self.session = session
        return session
    }

    private func prepare(
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        self.info = info
        guard let video = info.dashVideoFormat,
              let audio = info.dashAudioFormat,
              let stream = Self.stream(from: info, video: video) else {
            completion(.failure(SABRError.server("player response carries no SABR stream")))
            return
        }
        // Audio-only is left out: it needs the video track stripped from the
        // pair, which the session does not model yet.
        availableQualities = AndroidVRSource.qualities(from: info)
            .filter { $0.id != AudioOnlyMode.quality.id }
        currentQuality = availableQualities.first { "\($0.id)" == "\(video.itag)" }
            ?? VideoQuality(
                id: "\(video.itag)",
                label: video.qualityLabel ?? "\(video.height ?? 0)p",
                height: video.height,
                fps: video.fps
            )
        // No identity probe here, unlike the legacy path. Measured 2026-08-14:
        // SABR serves media regardless of what the probe says — identities the
        // probe rejects with 403 stream fine over SABR, including one burned
        // down deliberately. Probing would only cost a request and pointless
        // re-draws on start.
        openAndStart(stream, completion: completion)
    }

    private func openAndStart(
        _ stream: Stream,
        resumeAt: Int = 0,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let info else {
            completion(.failure(SABRError.server("playback info went away")))
            return
        }
        let session = openSession(stream)
        session.start(resumeAt: resumeAt) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let inits):
                self?.buildPlayback(
                    stream, session: session, inits: inits, completion: completion
                )
            }
        }
    }

    /// Playback moving to another video drops this source; the loopback server
    /// has to go with it rather than linger until collection.
    deinit {
        server?.stop()
    }
}
