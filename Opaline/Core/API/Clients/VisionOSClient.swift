import Foundation

/// Apple Vision Pro's client, played anonymously.
///
/// The one anonymous client googlevideo still serves past the first minute of
/// a video: measured 2026-08-18 against android_vr, android and ios, all of
/// which stop between 59904 ms and 69888 ms while this one plays through
/// (Opaline#76). Its formats carry URLs, so it can be fetched either way —
/// byte ranges or SABR.
struct VisionOSClient: PlaybackClient {
    let name = "VISIONOS"
    let version = "1.02"
    let headerName = "101"
    let userAgent = UserAgent.visionOS
    let playerURL = "\(InnertubeEndpoint.player)?prettyPrint=false"
    let authorization = PlaybackAuthorization.anonymous
    /// The jar holds whatever else has been on the wire; a session-bound URL
    /// is not what an anonymous client can play.
    let sendsCookies = false
    let listsAudioTracks = true

    var innertubeContext: [String: Any] { InnertubeContexts.visionOS }

    func sabrClientInfo() -> Data {
        var info = Protobuf.string(12, "Apple")
        info += Protobuf.string(13, "RealityDevice14,1")
        info += Protobuf.int(16, 101)
        info += Protobuf.string(17, version)
        info += Protobuf.string(18, "visionOS")
        info += Protobuf.string(19, "1.0.2.21O209")
        return info + SABRClientInfo.commonTail()
    }

    func sabrAbrState(
        video: SabrFormatInfo, audioTrackId: String?, playerMs: Int
    ) -> Data {
        var state = Protobuf.int(28, playerMs)
        if let height = video.height, height > 0 {
            state += Protobuf.int(21, height)      // stickyResolution
        }
        state += Protobuf.bool(22, false)          // clientViewportIsFlexible
        state += Protobuf.int(34, 1)               // visibility
        state += Protobuf.float(35, 1.0)           // playbackRate
        state += Protobuf.int(40, 0)               // enabledTrackTypes: audio + video
        if let audioTrackId, !audioTrackId.isEmpty {
            state += Protobuf.string(69, audioTrackId)
        }
        return state
    }
}
