import AVFoundation
import Foundation

// MARK: - PlaybackContext

/// The side-effects a `VideoSource`-driven playback needs from its host view
/// controller (WatchViewController conforms).
protocol PlaybackContext: AnyObject {
    /// Attaches a source-prepared item, retaining its resource loader; seeks to
    /// `resumeAt` when set (quality switches keep the current position).
    func attachPrepared(_ prepared: PreparedPlayback, resumeAt: CMTime?)
    func updateStatusLabel(_ text: String)
    func showPlaybackError(_ message: String)
    func startObservingPlayerItem(_ item: AVPlayerItem)
    func stopObservingPlayerItem(_ item: AVPlayerItem)
    func setCaptionTracks(_ tracks: [SubtitleTrack])
}
