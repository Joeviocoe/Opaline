import Foundation

/// What we already hold for one stream, so the server knows where to resume.
struct SABRStreamProgress {
    let format: SabrFormatInfo
    let lastSequence: Int
    let bufferedMs: Int
}

/// Who a SABR session streams as. Held per session rather than globally: a
/// composite can run an android_vr session and a TV one at the same time, and
/// a shared client would have each rewriting the other's requests.
struct SABRIdentity {
    /// Which client's session these requests belong to; the bodies carry it in
    /// `streamerContext`.
    let client: DirectPlaybackClient
    /// The proof-of-origin token, already decoded from its web-safe base64. A
    /// television sends it on every request, bound to the same id its `/player`
    /// call named; android_vr sends none, which is why it is the one client
    /// that plays without minting anything.
    let poToken: Data?
}

/// Builds `VideoPlaybackAbrRequest` bodies.
///
/// Field numbers are YouTube's, verified against a live server — see
/// `docs/plans/issue-78-sabr.md`. They are inlined next to each message rather
/// than named constants because they only mean anything in that one position.
enum SABRRequest {
    /// Everything the server needs to resume where the session left off.
    struct Continuation {
        let audio: SABRStreamProgress
        let video: SABRStreamProgress
        let playerMs: Int
        let playbackCookie: Data?
    }

    /// The first request of a session.
    ///
    /// Deliberately carries neither `selectedFormatIds` (2) nor `bufferedRanges`
    /// (3): either one tells the server the format is already playing, and it
    /// then withholds `FORMAT_INITIALIZATION_METADATA` and starts at the first
    /// media byte — leaving us with segments we cannot initialize a decoder
    /// from. Preferred audio/video (16/17) is enough to pick the formats.
    static func startup(
        ustreamerConfig: Data,
        audio: SabrFormatInfo,
        video: SabrFormatInfo,
        identity: SABRIdentity,
        playbackCookie: Data? = nil
    ) -> Data {
        var body = Protobuf.bytes(
            1, clientAbrState(video: video, playerMs: 0, identity: identity)
        )
        body += Protobuf.bytes(5, ustreamerConfig)
        body += Protobuf.bytes(16, formatId(audio))
        body += Protobuf.bytes(17, formatId(video))
        body += Protobuf.bytes(
            19, streamerContext(playbackCookie: playbackCookie, identity: identity)
        )
        return body
    }

    // swiftlint:disable function_parameter_count
    /// Jumps the stream to `playerMs`.
    ///
    /// A startup request cannot do this — with a non-zero player time it comes
    /// back empty (verified 2026-08-14). What works is a continuation that
    /// claims everything up to the target is already buffered, which is true
    /// enough: the player is not going to ask for those bytes.
    static func jump(
        ustreamerConfig: Data,
        audio: SabrFormatInfo,
        video: SabrFormatInfo,
        identity: SABRIdentity,
        playerMs: Int,
        sequence: Int = 1
    ) -> Data {
        let held = SABRStreamProgress(
            format: audio, lastSequence: sequence, bufferedMs: playerMs
        )
        let heldVideo = SABRStreamProgress(
            format: video, lastSequence: sequence, bufferedMs: playerMs
        )
        // swiftlint:enable function_parameter_count
        return continuation(
            ustreamerConfig: ustreamerConfig,
            state: Continuation(
                audio: held, video: heldVideo, playerMs: playerMs, playbackCookie: nil
            ),
            identity: identity
        )
    }

    /// Every request after the first: same shape plus what we already have.
    static func continuation(
        ustreamerConfig: Data, state: Continuation, identity: SABRIdentity
    ) -> Data {
        let (audio, video) = (state.audio, state.video)
        var body = Protobuf.bytes(
            1,
            clientAbrState(
                video: video.format, playerMs: state.playerMs, identity: identity
            )
        )
        for stream in [audio, video] {
            body += Protobuf.bytes(2, formatId(stream.format))
        }
        for stream in [audio, video] {
            body += Protobuf.bytes(3, bufferedRange(stream))
        }
        body += Protobuf.bytes(5, ustreamerConfig)
        body += Protobuf.bytes(16, formatId(audio.format))
        body += Protobuf.bytes(17, formatId(video.format))
        body += Protobuf.bytes(
            19,
            streamerContext(playbackCookie: state.playbackCookie, identity: identity)
        )
        return body
    }

    // MARK: - Messages

    private static func clientAbrState(
        video: SabrFormatInfo, playerMs: Int, identity: SABRIdentity
    ) -> Data {
        identity.client == .tv
            ? tvAbrState(video: video, playerMs: playerMs)
            : androidVRAbrState(video: video, playerMs: playerMs)
    }

    /// Field for field what a television sends, captured from a live TV session
    /// 2026-08-16. The set it uses is not the one android_vr uses — no
    /// `enabledTrackTypes`, `visibility` is 0 rather than 1, and it states DRC
    /// and codec preferences the other client leaves out.
    private static func tvAbrState(video: SabrFormatInfo, playerMs: Int) -> Data {
        var state = Protobuf.int(18, 1_920)        // clientViewportWidth
        state += Protobuf.int(19, 1_080)           // clientViewportHeight
        state += Protobuf.int(21, 0)               // stickyResolution
        if let bitrate = video.bitrate, bitrate > 0 {
            state += Protobuf.int(23, bitrate)     // bandwidthEstimate
        }
        state += Protobuf.int(28, playerMs)
        state += Protobuf.int(34, 0)               // visibility
        state += Protobuf.bool(46, true)           // drcEnabled
        state += Protobuf.bool(58, false)          // preferVp9
        state += Protobuf.int(59, decodeCeiling()) // av1QualityThreshold
        state += Protobuf.bytes(72, decodeCeilings())
        state += Protobuf.int(73, 2)
        state += Protobuf.bytes(79, playbackAuthorization())
        state += Protobuf.int(80, 1)
        state += Protobuf.int(85, 1)
        return state
    }

    /// The height this session may be served up to: a real television claims
    /// 1080, and claiming less than it would be asking the server to withhold
    /// formats we can play — so the setting only ever raises the ceiling.
    private static func decodeCeiling() -> Int {
        max(1_080, VideoQualityStore.maxHeight ?? 1_080)
    }

    /// What the set can decode — the shape a television sends, with our own
    /// ceiling in place of its fixed 1080.
    private static func decodeCeilings() -> Data {
        var caps = Protobuf.int(1, 0)
        caps += Protobuf.int(2, decodeCeiling())
        caps += Protobuf.int(3, 0)
        caps += Protobuf.int(4, 0)
        caps += Protobuf.int(5, decodeCeiling())
        caps += Protobuf.int(6, 0)
        return caps
    }

    /// `PlaybackAuthorization`: which track types this client may be served, and
    /// whether HDR is allowed for each. A television claims audio, SDR video and
    /// HDR video — the same three entries every time.
    private static func playbackAuthorization() -> Data {
        let entries = [(1, false), (2, false), (2, true)]
        return entries.reduce(Data()) { authorization, entry in
            var format = Protobuf.int(1, entry.0)   // trackType
            format += Protobuf.bool(2, entry.1)     // isHdr
            return authorization + Protobuf.bytes(1, format)
        }
    }

    private static func androidVRAbrState(video: SabrFormatInfo, playerMs: Int) -> Data {
        var state = Protobuf.int(28, playerMs)
        if let height = video.height, height > 0 {
            state += Protobuf.int(21, height)      // stickyResolution
        }
        state += Protobuf.bool(22, false)          // clientViewportIsFlexible
        state += Protobuf.int(34, 1)               // visibility
        state += Protobuf.float(35, 1.0)           // playbackRate
        state += Protobuf.int(40, 0)               // enabledTrackTypes: audio + video
        return state
    }

    private static func formatId(_ format: SabrFormatInfo) -> Data {
        var data = Protobuf.int(1, format.itag)
        if let lastModified = format.lastModified, let value = Int(lastModified) {
            data += Protobuf.int(2, value)
        }
        if let xtags = format.xtags, !xtags.isEmpty {
            data += Protobuf.string(3, xtags)
        }
        return data
    }

    private static func bufferedRange(_ stream: SABRStreamProgress) -> Data {
        var range = Protobuf.bytes(1, formatId(stream.format))
        range += Protobuf.int(2, 0)                       // startTimeMs
        range += Protobuf.int(3, stream.bufferedMs)       // durationMs
        range += Protobuf.int(4, 1)                       // startSegmentIndex
        range += Protobuf.int(5, stream.lastSequence)     // endSegmentIndex
        var timeRange = Protobuf.int(1, 0)
        timeRange += Protobuf.int(2, stream.bufferedMs)
        timeRange += Protobuf.int(3, 1_000)                // timescale
        return range + Protobuf.bytes(6, timeRange)
    }

    private static func streamerContext(
        playbackCookie: Data?, identity: SABRIdentity
    ) -> Data {
        var context = Protobuf.bytes(1, clientInfo(identity: identity))
        if let poToken = identity.poToken, !poToken.isEmpty {
            context += Protobuf.bytes(2, poToken)
        }
        if let playbackCookie, !playbackCookie.isEmpty {
            context += Protobuf.bytes(3, playbackCookie)
        }
        return context
    }

    /// Describes the client the SABR URL was minted for — it has to match the
    /// /player call, the server reads this to size and sign what it serves.
    private static func clientInfo(identity: SABRIdentity) -> Data {
        identity.client == .tv ? tvClientInfo() : androidVRClientInfo()
    }

    private static func tvClientInfo() -> Data {
        var info = Protobuf.int(16, 7)
        info += Protobuf.string(17, DirectPlaybackClient.tv.clientVersion)
        info += Protobuf.string(18, "Cobalt")
        info += Protobuf.string(19, "22.lts.3.306369-gold")
        info += Protobuf.string(21, "en-US")
        info += Protobuf.string(22, "US")
        info += Protobuf.int(37, 1_920)
        info += Protobuf.int(38, 1_080)
        info += Protobuf.int(41, 1)
        info += Protobuf.int(46, 2)
        info += Protobuf.int(55, 1_920)
        info += Protobuf.int(56, 1_080)
        info += Protobuf.float(65, 1.0)
        return info
    }

    private static func androidVRClientInfo() -> Data {
        var info = Protobuf.string(12, "Oculus")
        info += Protobuf.string(13, "Quest 3")
        info += Protobuf.int(16, 28)
        info += Protobuf.string(17, DirectPlaybackClient.androidVR.clientVersion)
        info += Protobuf.string(18, "Android")
        info += Protobuf.string(19, "12L")
        info += Protobuf.string(21, "en-US")
        info += Protobuf.string(22, "US")
        info += Protobuf.int(37, 1_920)
        info += Protobuf.int(38, 1_080)
        info += Protobuf.int(41, 1)
        info += Protobuf.int(46, 2)
        info += Protobuf.int(55, 1_920)
        info += Protobuf.int(56, 1_080)
        info += Protobuf.float(65, 1.0)
        return info
    }
}
