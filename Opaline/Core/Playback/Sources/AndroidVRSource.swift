import AVFoundation
import Foundation

/// Innertube android_vr source: fetches adaptive DASH formats and plays them as
/// a SIDX-generated HLS stream (with native-HLS / progressive fallbacks). Owns
/// quality selection from the DASH ladder.
final class AndroidVRSource: VideoSource {
    private static let noStreamError = NSError(
        domain: "AndroidVRSource",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "No playable stream"]
    )

    let kind: VideoSourceKind = .androidVR
    var supportsQualitySelection: Bool { !availableQualities.isEmpty }
    var currentCodecs: String? {
        guard let line = Self.codecsLine(info: info, quality: currentQuality) else {
            return nil
        }
        guard let delivery, delivery.label != "range" else {
            return line
        }
        return "\(line) [\(delivery.label)]"
    }
    private(set) var availableQualities: [VideoQuality] = []
    private(set) var currentQuality: VideoQuality?

    private let apiClient: WatchService
    let transport: HTTPTransport
    /// How the bytes are arriving right now — byte ranges or SABR.
    var delivery: StreamDelivery?
    private let liveHLS: LiveHLSPlayback
    private let client: DirectPlaybackClient = .androidVR
    private var info: DirectPlaybackInfo?

    init(
        apiClient: WatchService,
        transport: HTTPTransport = ServiceContainer.mediaTransport,
        resolver: HLSStreamResolver = .shared
    ) {
        self.apiClient = apiClient
        self.transport = transport
        liveHLS = LiveHLSPlayback(resolver: resolver)
    }

    /// "vCodec (itag) / aCodec (itag)" for the stats overlay; nil when the
    /// active quality is not a DASH format (live variants). `audio` overrides
    /// the default audio format (mweb after an audio-track switch).
    static func codecsLine(
        info: DirectPlaybackInfo?,
        quality: VideoQuality?,
        audio: DashFormatInfo? = nil
    ) -> String? {
        guard let info, let quality,
              let video = info.allDashVideoFormats.first(
                  where: { "\($0.itag)" == quality.id }
              ) else {
            return nil
        }
        let videoPart = "\(video.codecs) (\(video.itag))"
        guard let audio = audio ?? info.dashAudioFormat else {
            return videoPart
        }
        return videoPart + " / \(audio.codecs) (\(audio.itag))"
    }

    /// One entry per tier label: with av01 admitted alongside avc1 the same
    /// height appears twice — keep the first (higher-bitrate) format.
    ///
    /// Audio-only leads the list. It needs a DASH pair to strip the video from,
    /// so live and progressive videos never offer it.
    static func qualities(from info: DirectPlaybackInfo) -> [VideoQuality] {
        let tiers = videoTiers(from: info)
        guard !tiers.isEmpty, info.dashAudioFormat != nil else {
            return tiers
        }
        return [AudioOnlyMode.quality] + tiers
    }

    private static func videoTiers(from info: DirectPlaybackInfo) -> [VideoQuality] {
        var seenLabels = Set<String>()
        return info.allDashVideoFormats.map { format in
            let fps = format.fps ?? 0
            let height = format.height ?? 0
            // YouTube's tier name when present — non-16:9 heights are
            // off-ladder (1920x1012 is the "1080p" tier, not "1012p").
            let fallback = fps > 30 ? "\(height)p\(fps)" : "\(height)p"
            return VideoQuality(
                id: "\(format.itag)",
                label: format.qualityLabel ?? fallback,
                height: format.height,
                fps: format.fps
            )
        }
        .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        .filter { seenLabels.insert($0.label).inserted }
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        apiClient.fetchDirectPlayback(
            videoId: videoId,
            client: client,
            poToken: nil,
            cancellationToken: cancellation
        ) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let info):
                self?.handleInfo(info, completion: completion)
            }
        }
    }

    func releaseResources() {
        releaseDelivery()
    }

    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if liveHLS.isActive {
            selectLiveQuality(quality, completion: completion)
            return
        }
        guard let info,
              let format = AudioOnlyMode.resolveFormat(
                  for: quality, info: info, current: currentQuality
              ),
              let audio = info.dashAudioFormat else {
            completion(.failure(Self.noStreamError))
            return
        }
        currentQuality = quality
        buildGeneratedHLS(
            info: info,
            video: format,
            audio: audio,
            resumeAt: resumeAt,
            completion: completion
        )
    }

    // MARK: - Private

    private func handleInfo(
        _ info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        self.info = info
        liveHLS.reset()
        availableQualities = Self.qualities(from: info)
        let defaultQuality = info.dashVideoFormat.flatMap { selected in
            availableQualities.first { $0.id == "\(selected.itag)" }
        }
        currentQuality = AudioOnlyMode.startQuality(
            in: availableQualities, fallback: defaultQuality
        )
        buildBest(info: info, completion: completion)
    }

    private func buildBest(
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if let video = info.dashVideoFormat, let audio = info.dashAudioFormat {
            buildGeneratedHLS(
                info: info, video: video, audio: audio, completion: completion
            )
        } else if let hls = info.hlsManifestURL {
            loadLiveHLS(info: info, url: hls, completion: completion)
        } else if let progressive = info.progressiveURL {
            let item = progressiveItem(progressive, info: info)
            completion(.success(prepared(item: item, info: info)))
        } else {
            completion(.failure(Self.noStreamError))
        }
    }

    private func buildGeneratedHLS(
        info: DirectPlaybackInfo,
        video: DashFormatInfo,
        audio: DashFormatInfo,
        resumeAt: Double? = nil,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        deliver(
            DeliveryRequest(info: info, video: video, audio: audio, resumeAt: resumeAt),
            completion: completion
        )
    }

    private func progressiveItem(
        _ url: URL, info: DirectPlaybackInfo
    ) -> AVPlayerItem {
        let headers = client.streamHeaders(visitorData: info.visitorData)
        let asset = AVURLAsset(
            url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return AVPlayerItem(asset: asset)
    }

    private func prepared(
        item: AVPlayerItem, info: DirectPlaybackInfo
    ) -> PreparedPlayback {
        PreparedPlayback(
            item: item, captions: info.captionTracks, duration: info.duration
        )
    }
}

// MARK: - Live HLS

private extension AndroidVRSource {
    /// Live streams (no DASH SIDX ladder): [[LiveHLSPlayback]] exposes the
    /// multivariant playlist's variants as qualities and starts on Auto. A
    /// failed playlist fetch degrades to direct playback with no picker.
    func loadLiveHLS(
        info: DirectPlaybackInfo,
        url: URL,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        liveHLS.load(url: url, info: info) { [weak self] prepared in
            guard let self else {
                return
            }
            if !liveHLS.qualities.isEmpty {
                availableQualities = liveHLS.qualities
                currentQuality = liveHLS.startQuality
            }
            completion(.success(prepared))
        }
    }

    func selectLiveQuality(
        _ quality: VideoQuality,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let info,
              let prepared = liveHLS.prepared(for: quality, info: info) else {
            completion(.failure(Self.noStreamError))
            return
        }
        currentQuality = quality
        completion(.success(prepared))
    }
}
