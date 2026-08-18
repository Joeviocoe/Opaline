import Foundation

/// The phone client, used for the muxed 360p stream and nothing else.
///
/// Its adaptive formats are held to the anonymous one-minute quota like every
/// other phone client, but the muxed `itag 18` URL is not: 12 MiB pulled in
/// sequence, no refusal (measured 2026-08-18, Opaline#76). That single stream
/// is the whole reason this client exists here.
struct AndroidClient: PlaybackClient {
    let name = "ANDROID"
    let version = "21.26.364"
    let headerName = "3"
    let userAgent = UserAgent.androidPhone
    let playerURL = "\(InnertubeEndpoint.player)?prettyPrint=false"
    let authorization = PlaybackAuthorization.anonymous
    let sendsCookies = false

    var innertubeContext: [String: Any] { InnertubeContexts.android }

    /// Never opens a SABR session — the muxed stream is a plain URL — so the
    /// protobuf identity is only here to satisfy the protocol.
    func sabrClientInfo() -> Data {
        var info = Protobuf.int(16, 3)
        info += Protobuf.string(17, version)
        info += Protobuf.string(18, "Android")
        info += Protobuf.string(19, "11")
        return info + SABRClientInfo.commonTail()
    }

    func sabrAbrState(_ state: SABRPlayerState) -> Data {
        var body = Protobuf.int(28, state.playerMs)
        if let height = state.video.height, height > 0 {
            body += Protobuf.int(21, height)             // stickyResolution
        }
        body += Protobuf.bool(22, false)                 // clientViewportIsFlexible
        body += Protobuf.int(34, 1)                      // visibility
        body += Protobuf.float(35, 1.0)                  // playbackRate
        body += Protobuf.int(40, state.wants.bitfield)   // enabledTrackTypes
        if let id = state.audioTrackId, !id.isEmpty {
            body += Protobuf.string(69, id)
        }
        return body
    }
}
