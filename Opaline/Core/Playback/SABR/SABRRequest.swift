import Foundation

/// What the last response delivered for one stream.
///
/// This is what a request acknowledges, and it is deliberately *not* a running
/// total: the server tracks the whole picture itself through the playback
/// cookie, and only needs to hear which segments just landed. Claiming
/// everything from zero instead — as this once did — states that the bytes
/// behind the playhead are already held, so the server never sends them again
/// and rewinding cannot work at all.
struct SABRBufferedRange {
    let format: SabrFormatInfo
    let startMs: Int
    let durationMs: Int
    let startSequence: Int
    let endSequence: Int
    let timescale: Int
}

/// Who a SABR session streams as. Held per session rather than globally: a
/// chain can run an anonymous session and a TV one at the same time, and
/// a shared client would have each rewriting the other's requests.
struct SABRIdentity {
    /// Which client's session these requests belong to; the bodies carry it in
    /// `streamerContext`.
    let client: PlaybackClient
    /// The proof-of-origin token, already decoded from its web-safe base64. A
    /// television sends it on every request, bound to the same id its `/player`
    /// call named; the anonymous clients send none, which is why they play
    /// without minting anything.
    let poToken: Data?
}

/// Builds `VideoPlaybackAbrRequest` bodies.
///
/// Field numbers are YouTube's, verified against a live server — see
/// `docs/plans/issue-78-sabr.md`. They are inlined next to each message rather
/// than named constants because they only mean anything in that one position.
enum SABRRequest {
    /// One segment's worth of request: which format it is for, what is already
    /// held of it, and where the player wants bytes from.
    struct Fetch {
        let format: SabrFormatInfo
        /// The stream this request is *not* about.
        let other: SabrFormatInfo
        /// The last segment received of `format`, acknowledged so the server
        /// carries on rather than resending it.
        let held: SABRBufferedRange?
        let isInit: Bool
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
            1, identity.client.sabrAbrState(
                SABRPlayerState(
                    video: video,
                    audioTrackId: audio.audioTrackId,
                    wants: .both,
                    playerMs: 0
                )
            )
        )
        body += Protobuf.bytes(5, ustreamerConfig)
        body += Protobuf.bytes(16, formatId(audio))
        body += Protobuf.bytes(17, formatId(video))
        body += Protobuf.bytes(
            19, streamerContext(playbackCookie: playbackCookie, identity: identity)
        )
        return body
    }

    /// A request for one segment of one format.
    ///
    /// The other format is declined rather than merely not asked for: a
    /// buffered range claiming all of it, which is what googlevideo's own
    /// adapter sends to mean "do not send this one". Without it every request
    /// for a video segment also drags the audio down, and the response is
    /// several times the size of what was wanted.
    static func segment(
        ustreamerConfig: Data, state: Fetch, identity: SABRIdentity
    ) -> Data {
        let isVideo = state.format.height ?? 0 > 0
        let video = isVideo ? state.format : state.other
        let audio = isVideo ? state.other : state.format
        var body = Protobuf.bytes(
            1, identity.client.sabrAbrState(
                SABRPlayerState(
                    video: video,
                    audioTrackId: audio.audioTrackId,
                    // One request, one track — the server is told exactly
                    // which, as googlevideo's own adapter does.
                    wants: isVideo ? .video : .audio,
                    playerMs: state.playerMs
                )
            )
        )
        body += Protobuf.bytes(2, formatId(state.other))
        // An init request must not claim the format is playing, or the server
        // withholds the initialization metadata and starts at the first media
        // byte — leaving a segment no decoder can be built from.
        if !state.isInit {
            body += Protobuf.bytes(2, formatId(state.format))
        }
        body += Protobuf.bytes(3, fullBufferedRange(state.other))
        if let held = state.held {
            body += Protobuf.bytes(3, bufferedRange(held))
        }
        body += Protobuf.bytes(5, ustreamerConfig)
        body += Protobuf.bytes(16, formatId(audio))
        body += Protobuf.bytes(17, formatId(video))
        body += Protobuf.bytes(
            19,
            streamerContext(playbackCookie: state.playbackCookie, identity: identity)
        )
        return body
    }

    /// A range claiming the whole of a format is already held, so the server
    /// sends none of it.
    private static func fullBufferedRange(_ format: SabrFormatInfo) -> Data {
        let max = Int(Int32.max)
        var range = Protobuf.bytes(1, formatId(format))
        range += Protobuf.int(2, 0)                       // startTimeMs
        range += Protobuf.int(3, max)                     // durationMs
        range += Protobuf.int(4, max)                     // startSegmentIndex
        range += Protobuf.int(5, max)                     // endSegmentIndex
        var timeRange = Protobuf.int(1, 0)
        timeRange += Protobuf.int(2, max)
        timeRange += Protobuf.int(3, 1_000)
        return range + Protobuf.bytes(6, timeRange)
    }

    // MARK: - Messages

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

    private static func bufferedRange(_ delivery: SABRBufferedRange) -> Data {
        var range = Protobuf.bytes(1, formatId(delivery.format))
        range += Protobuf.int(2, delivery.startMs)         // startTimeMs
        range += Protobuf.int(3, delivery.durationMs)      // durationMs
        range += Protobuf.int(4, delivery.startSequence)   // startSegmentIndex
        range += Protobuf.int(5, delivery.endSequence)     // endSegmentIndex
        var timeRange = Protobuf.int(1, delivery.startMs)  // startTicks
        timeRange += Protobuf.int(2, delivery.durationMs)  // durationTicks
        timeRange += Protobuf.int(3, delivery.timescale)
        return range + Protobuf.bytes(6, timeRange)
    }

    private static func streamerContext(
        playbackCookie: Data?, identity: SABRIdentity
    ) -> Data {
        var context = Protobuf.bytes(1, identity.client.sabrClientInfo())
        if let poToken = identity.poToken, !poToken.isEmpty {
            context += Protobuf.bytes(2, poToken)
        }
        if let playbackCookie = playbackCookie, !playbackCookie.isEmpty {
            context += Protobuf.bytes(3, playbackCookie)
        }
        return context
    }
}
