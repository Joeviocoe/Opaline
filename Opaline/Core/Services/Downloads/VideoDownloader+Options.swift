import Foundation

// MARK: - Rendition picking

extension VideoDownloader {
    /// H.264 video paired with the original-language AAC audio.
    ///
    /// AV1 and VP9 are left out on purpose: `AVAssetExportSession` will not
    /// pass them through into an MP4, and on the devices this app targets a
    /// software AV1 decode is not something to hand someone offline.
    static func options(in info: DirectPlaybackInfo) -> [DownloadOption] {
        guard let audio = audioFormat(in: info) else {
            return []
        }
        var best: [Int: DashFormatInfo] = [:]
        for format in info.allDashVideoFormats
            where format.hasDirectURL
            && format.codecs.hasPrefix("avc1")
            && format.sigChallenge == nil {
            guard let height = format.height else {
                continue
            }
            if let current = best[height], current.bitrate >= format.bitrate {
                continue
            }
            best[height] = format
        }
        return best.values
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
            .map {
                DownloadOption(
                    label: $0.qualityLabel ?? "\($0.height ?? 0)p",
                    height: $0.height ?? 0,
                    video: $0,
                    audio: audio
                )
            }
    }

    /// The dub the video would start on, judged the same way a live playback
    /// judges it. A saved copy holds one audio track, so it has to be the one
    /// this person would have heard: downloading the original of an English
    /// video that plays back in Russian gives them a file they cannot watch.
    private static func audioFormat(
        in info: DirectPlaybackInfo
    ) -> DashFormatInfo? {
        let mp4 = info.allDashAudioFormats.filter {
            $0.hasDirectURL && $0.codecs.hasPrefix("mp4a")
        }
        let dubbed = AutoDubPreference
            .autoDubTrack(in: mp4.compactMap(track))
            .flatMap { wanted in
                mp4.first { $0.audioTrackId == wanted.id }
            }
        let original = mp4.first { $0.audioIsOriginal }
        let fallback = info.dashAudioFormat.flatMap {
            $0.hasDirectURL && $0.codecs.hasPrefix("mp4a") ? $0 : nil
        }
        if let dubbed = dubbed {
            AppLog.downloads("saving the \(dubbed.audioTrackId ?? "?") dub")
        }
        return dubbed ?? original ?? mp4.first ?? fallback
    }

    private static func track(_ format: DashFormatInfo) -> AudioTrack? {
        guard let id = format.audioTrackId else {
            return nil
        }
        return AudioTrack(
            id: id,
            displayName: format.audioTrackName ?? id,
            isDefault: format.audioIsDefault
        )
    }
}
