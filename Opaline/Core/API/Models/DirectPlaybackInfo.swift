import Foundation

// MARK: - Playback / streaming-data models
//
// Parsed from /player responses (InnertubeClientPlayerParsing). Split from
// Video.swift purely by domain: these are streaming formats, not tiles.

struct DashFormatInfo {
    let url: URL
    let itag: Int
    let mimeType: String       // e.g. "video/mp4; codecs=\"avc1.4d401f\""
    let codecs: String         // e.g. "avc1.4d401f"
    let bitrate: Int
    let contentLength: Int64
    let initRangeEnd: Int      // e.g. 739
    let indexRangeStart: Int   // e.g. 740
    let indexRangeEnd: Int     // e.g. 11739
    let width: Int?
    let height: Int?
    let fps: Int?
    /// YouTube's own tier name ("1080p", "1080p60"). Preferred over deriving
    /// from `height` — non-16:9 videos have off-ladder heights (1920x1012 is
    /// still the "1080p" tier, not "1012p").
    let qualityLabel: String?
    /// Ciphered `s` challenge when the format arrived as a `signatureCipher`
    /// (mweb; kids content) — `url` 403s until the solved value is appended
    /// as the `sigParam` query parameter.
    let sigChallenge: String?
    /// Query-param name for the solved signature (`sp` from the cipher).
    let sigParam: String?
    /// `audioTrack` metadata on dubbed audio formats — nil on video formats
    /// and on videos without dubs. `audioTrackId` is YouTube's track id
    /// ("ru.3"), `audioTrackName` its localized display name ("Russian").
    /// `audioIsDefault` follows the request's `hl`, NOT the upload language.
    let audioTrackId: String?
    let audioTrackName: String?
    let audioIsDefault: Bool

    /// The upload-language track — id suffix ".4" (`acont=original`).
    var audioIsOriginal: Bool { audioTrackId?.hasSuffix(".4") == true }
}

struct DirectPlaybackInfo {
    let hlsManifestURL: URL?
    let dashManifestURL: URL?
    let progressiveURL: URL?
    let videoURL: URL?
    let audioURL: URL?
    let serverAbrStreamingURL: URL?
    let videoPlaybackUstreamerConfig: String?
    let onesieUstreamerConfig: String?
    let sabrVideoFormat: SabrFormatInfo?
    let sabrAudioFormat: SabrFormatInfo?
    let videoItag: Int?
    let audioItag: Int?
    let qualityLabel: String?
    let visitorData: String?
    let hasPlaybackUstreamerConfig: Bool
    let dashVideoFormat: DashFormatInfo?
    let dashAudioFormat: DashFormatInfo?
    let allDashVideoFormats: [DashFormatInfo]
    /// Best audio/mp4 format per distinct audio track (dub) — one entry per
    /// language, original track first. Empty when the video has no track
    /// metadata (single-audio videos still populate `dashAudioFormat`).
    let allDashAudioFormats: [DashFormatInfo]
    let duration: Double?
    let playbackTrackingURLs: WatchtimeURLs?
    let captionTracks: [SubtitleTrack]
}

/// Distinct audio-track (dub) metadata from a /player response — the listing
/// only, no playable formats attached.
struct AudioTrackInfo {
    let id: String
    let displayName: String
    let isDefault: Bool
}

struct WatchtimeURLs {
    let playbackURL: String
    let watchtimeURL: String
    let duration: Double?
}

struct SabrFormatInfo {
    let itag: Int
    let lastModified: String?
    let xtags: String?
    let audioTrackId: String?
    let isDrc: Bool
    let mimeType: String?
    let bitrate: Int?
    let width: Int?
    let height: Int?
}
