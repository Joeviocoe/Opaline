import Foundation

/// One video/audio pair to play, and where to start.
struct DeliveryRequest {
    let info: DirectPlaybackInfo
    let video: DashFormatInfo
    let audio: DashFormatInfo
    /// Playhead to resume at — set when this replaces playback already in
    /// progress (a quality switch), nil when starting fresh.
    let resumeAt: Double?
}

/// How a resolved player response becomes playable bytes.
///
/// This is the second axis of playback, independent of the first. A
/// `VideoSource` decides *who we ask* — which Innertube client, with what
/// authentication — and that governs which formats, dubs and restrictions come
/// back. A `StreamDelivery` decides *how the bytes arrive*: byte-range requests
/// against `adaptiveFormats` URLs, or a SABR session.
///
/// Keeping them apart is what makes the fallback free. A source picks the
/// delivery that matches what the response actually carries, so if YouTube
/// stops handing out stream URLs — as it already did for `hlsManifestUrl` in
/// July — playback moves to SABR without a new source, a new setting, or any
/// user-visible change.
protocol StreamDelivery: AnyObject {
    /// Short name for logs and the stats overlay.
    var label: String { get }

    func prepare(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    )
}

/// Byte-range delivery over the `adaptiveFormats` URLs: fetch each stream's
/// `sidx`, generate a byte-range HLS playlist, let AVPlayer fetch the ranges.
///
/// Subject to googlevideo's per-identity quota, which is why the machinery
/// around it (`PlaybackFacade+Identity`) exists.
final class LegacyRangeDelivery: StreamDelivery {
    let label = "range"

    private let client: PlaybackClient

    init(client: PlaybackClient) {
        self.client = client
    }

    func prepare(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let info = request.info
        let input = HLSPlaybackBuilder.BuildInput(
            videoURL: client.directURL(baseURL: request.video.url, poToken: nil),
            audioURL: client.directURL(baseURL: request.audio.url, poToken: nil),
            videoFormat: request.video,
            audioFormat: request.audio,
            headers: client.streamHeaders(visitorData: info.visitorData),
            startAt: request.resumeAt
        )
        HLSPlaybackBuilder.build(input: input) { result in
            guard let result else {
                completion(.failure(StreamDeliveryError.noStream))
                return
            }
            completion(.success(PreparedPlayback(
                item: result.playerItem,
                resourceLoader: result.loader,
                captions: info.captionTracks,
                duration: info.duration
            )))
        }
    }
}

enum StreamDeliveryError: LocalizedError {
    case noStream

    var errorDescription: String? {
        "No playable stream"
    }
}
