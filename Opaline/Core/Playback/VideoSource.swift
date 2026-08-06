import AVFoundation
import Foundation

// MARK: - VideoSource contracts
//
// One interface every video source implements. A source owns its ENTIRE
// concern: resolving a playable stream AND its quality options (get/set). No
// source-specific branching leaks into the player shell or the UI — the view
// controller talks only to `VideoSource`.

/// Identifies a source; maps 1:1 from the user-facing `PlaybackSource` setting.
enum VideoSourceKind {
    /// Composite strategy: android_vr first, mweb+pot on failure. Only ever a
    /// factory input — a playing source always reports a concrete kind.
    case auto
    case androidVR
    case progressive
    case mwebPot
}

/// A selectable quality level, expressed source-agnostically.
struct VideoQuality: Equatable {
    let id: String
    let label: String
    let height: Int?
    let fps: Int?
}

/// A selectable audio track (dub), expressed source-agnostically.
struct AudioTrack: Equatable {
    /// YouTube's track id, e.g. "ru.3". The suffix encodes the track type
    /// (matches the `acont` value in the format's xtags): `.4` = original,
    /// `.3` = human dub, `.10` = AI auto-dub. Verified 2026-07-18.
    let id: String
    /// Localized display name, e.g. "Russian". Identical for human and AI
    /// dubs — the id suffix is the only distinguishing signal.
    let displayName: String
    /// YouTube's `audioIsDefault` — marks the track matching the REQUEST's
    /// `hl`, not the upload language (a Russian video probed with `hl=en`
    /// flags the English AI dub as default). Use [[isOriginal]] to find the
    /// upload-language track.
    let isDefault: Bool

    /// AI auto-dub (`acont=dubbed-auto`).
    var isAutoDubbed: Bool { id.hasSuffix(".10") }
    /// The upload-language track (`acont=original`).
    var isOriginal: Bool { id.hasSuffix(".4") }
}

/// A ready-to-play result handed back to the player shell. The shell attaches
/// `item` and retains `resourceLoader` for the item's lifetime.
struct PreparedPlayback {
    let item: AVPlayerItem
    let resourceLoader: AVAssetResourceLoaderDelegate?
    let captions: [SubtitleTrack]
    let duration: Double?

    init(
        item: AVPlayerItem,
        resourceLoader: AVAssetResourceLoaderDelegate? = nil,
        captions: [SubtitleTrack] = [],
        duration: Double? = nil
    ) {
        self.item = item
        self.resourceLoader = resourceLoader
        self.captions = captions
        self.duration = duration
    }
}

/// A single video source: resolves a stream and owns its quality selection.
protocol VideoSource: AnyObject {
    var kind: VideoSourceKind { get }
    /// Whether this source exposes a quality menu at all.
    var supportsQualitySelection: Bool { get }
    /// Qualities available for the currently loaded video (empty until loaded).
    var availableQualities: [VideoQuality] { get }
    /// The active quality, if any.
    var currentQuality: VideoQuality? { get }
    /// Active codec/itag pair for the stats overlay, when the source knows it.
    var currentCodecs: String? { get }
    /// Whether this source exposes an audio-track (dub) menu.
    var supportsAudioTrackSelection: Bool { get }
    /// Audio tracks for the currently loaded video (empty = single-audio).
    var availableAudioTracks: [AudioTrack] { get }
    /// The active audio track, if the source knows it.
    var currentAudioTrack: AudioTrack? { get }

    /// Resolves the video and produces a ready-to-play result.
    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    )

    /// Switches quality; the source rebuilds playback its own way.
    func selectQuality(
        _ quality: VideoQuality,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    )

    /// Switches the audio track; the source rebuilds playback its own way.
    func selectAudioTrack(
        _ track: AudioTrack,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    )

    /// Fetches audio-track metadata WITHOUT preparing playback — lets a
    /// composite discover dubs on a fallback source in the background while
    /// another source plays. Sources that never list dubs return `[]`.
    func probeAudioTracks(
        videoId: String,
        completion: @escaping ([AudioTrack]) -> Void
    )
}

extension VideoSource {
    var currentCodecs: String? { nil }

    // Audio-track selection is opt-in: sources whose client never returns
    // dub tracks (android_vr, progressive) inherit the disabled default.
    var supportsAudioTrackSelection: Bool { availableAudioTracks.count > 1 }
    var availableAudioTracks: [AudioTrack] { [] }
    var currentAudioTrack: AudioTrack? { nil }

    func selectAudioTrack(
        _ track: AudioTrack,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        completion(.failure(NSError(
            domain: "VideoSource",
            code: 0,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Audio track selection not supported"
            ]
        )))
    }

    func probeAudioTracks(
        videoId: String,
        completion: @escaping ([AudioTrack]) -> Void
    ) {
        completion([])
    }
}

/// Creates the right `VideoSource` for a kind (abstract factory).
protocol VideoSourceFactory {
    func make(kind: VideoSourceKind) -> VideoSource
}
