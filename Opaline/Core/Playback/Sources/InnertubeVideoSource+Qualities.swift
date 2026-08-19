import Foundation

// MARK: - The quality ladder a /player response describes

extension InnertubeVideoSource {
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

    /// One `/player` fetch, formats only — no delivery is opened and no state
    /// is published, so a probe racing a real load cannot disturb it.
    func probeQualities(
        videoId: String,
        completion: @escaping ([VideoQuality]) -> Void
    ) {
        fetchInfo(videoId: videoId, cancellation: nil) { result in
            DispatchQueue.main.async {
                guard case .success(let info) = result else {
                    completion([])
                    return
                }
                completion(Self.qualities(from: info))
            }
        }
    }
}
