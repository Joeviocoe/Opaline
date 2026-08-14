import Foundation

/// What we already hold for one stream, so the server knows where to resume.
struct SABRStreamProgress {
    let format: SabrFormatInfo
    let lastSequence: Int
    let bufferedMs: Int
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
        playbackCookie: Data? = nil
    ) -> Data {
        var body = Protobuf.bytes(1, clientAbrState(video: video, playerMs: 0))
        body += Protobuf.bytes(5, ustreamerConfig)
        body += Protobuf.bytes(16, formatId(audio))
        body += Protobuf.bytes(17, formatId(video))
        body += Protobuf.bytes(19, streamerContext(playbackCookie: playbackCookie))
        return body
    }

    /// Every request after the first: same shape plus what we already have.
    static func continuation(ustreamerConfig: Data, state: Continuation) -> Data {
        let (audio, video) = (state.audio, state.video)
        var body = Protobuf.bytes(
            1, clientAbrState(video: video.format, playerMs: state.playerMs)
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
        body += Protobuf.bytes(19, streamerContext(playbackCookie: state.playbackCookie))
        return body
    }

    // MARK: - Messages

    private static func clientAbrState(video: SabrFormatInfo, playerMs: Int) -> Data {
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

    private static func streamerContext(playbackCookie: Data?) -> Data {
        var context = Protobuf.bytes(1, clientInfo())
        if let playbackCookie, !playbackCookie.isEmpty {
            context += Protobuf.bytes(3, playbackCookie)
        }
        return context
    }

    /// ANDROID_VR, matching `DirectPlaybackClient.androidVR`. No PO token: this
    /// client is served without one, `visitorData` on the /player call is what
    /// keeps the identity valid.
    private static func clientInfo() -> Data {
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
