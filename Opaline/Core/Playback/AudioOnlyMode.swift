import Foundation

/// Audio-only playback: the generated HLS keeps its video playlist registered,
/// but the player is pointed at the audio-only entry, so no video segment is
/// ever fetched. Locking the screen does NOT do this — AVPlayer keeps pulling
/// the video track — which is exactly why the mode exists.
///
/// Modelled as a quality tier rather than a separate switch: it is the same
/// "how much data may this cost" decision the quality picker already owns.
enum AudioOnlyMode {
    /// Never an itag, so it can never collide with a real format id.
    static let qualityID = "audio"

    /// Session state: only ever a hint for the toggle, so it is not worth a
    /// defaults key.
    private static var lastVideoQualityID: String?

    /// Deliberately NOT persisted: the mode carries across videos so a queue
    /// plays through as sound, but a relaunch starts from the quality the
    /// settings say. A sticky mode surviving restarts reads as "the app broke
    /// and stopped showing video".
    static var isEnabled = false

    /// Both entries are always registered by the builder; pointing the player
    /// at the audio-only one leaves the video playlist unrequested, so not a
    /// single video segment is fetched.
    static var entryPlaylist: String {
        isEnabled ? "audio-master.m3u8" : "master.m3u8"
    }

    static var quality: VideoQuality {
        VideoQuality(
            id: qualityID,
            label: "player.quality.audioOnly".localized,
            height: nil,
            fps: nil
        )
    }

    /// The tier a freshly loaded video starts on: the mode outlives a single
    /// video, so it wins over the format the response defaulted to — but only
    /// where it is on offer (a live stream keeps its own ladder).
    static func startQuality(
        in qualities: [VideoQuality], fallback: VideoQuality?
    ) -> VideoQuality? {
        guard isEnabled,
              qualities.contains(where: { $0.id == qualityID }) else {
            return fallback
        }
        return quality
    }

    /// The DASH video format a quality pick should build with, flipping the
    /// mode on the way: picking "Audio only" keeps whatever video format is
    /// loaded (the build still needs one — only the entry playlist changes),
    /// picking a real tier switches back to it.
    static func resolveFormat(
        for quality: VideoQuality,
        info: DirectPlaybackInfo,
        current: VideoQuality?
    ) -> DashFormatInfo? {
        isEnabled = quality.id == qualityID
        let targetID = isEnabled ? current?.id : quality.id
        let format = info.allDashVideoFormats.first { "\($0.itag)" == targetID }
            ?? info.dashVideoFormat
        lastVideoQualityID = format.map { "\($0.itag)" }
        return format
    }

    /// The tier to return to when the mode is switched off — whichever one the
    /// audio-only build kept underneath. Falls back to the top of the ladder
    /// (a source loaded straight into audio-only never had another).
    static func videoQuality(in qualities: [VideoQuality]) -> VideoQuality? {
        qualities.first { $0.id == lastVideoQualityID }
            ?? qualities.first { $0.id != qualityID }
    }
}
