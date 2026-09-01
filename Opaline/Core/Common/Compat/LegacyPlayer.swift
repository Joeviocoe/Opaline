import AVFoundation
import CoreMedia
import MediaPlayer
import UIKit

#if LEGACY_IOS9
extension AVPlayer {
    /// iOS 10's three-state playback status, derived from what iOS 9 exposes.
    ///
    /// `rate` and `currentItem.status` together carry the same information:
    /// a non-zero rate with a ready item is playing, a non-zero rate with an
    /// item that is not ready is waiting, and a zero rate is paused.
    var timeControlStatus: LegacyTimeControlStatus {
        guard rate != 0 else {
            return .paused
        }
        return currentItem?.status == .readyToPlay ? .playing : .waitingToPlayAtSpecifiedRate
    }

    /// iOS 10. Before it, setting the rate is exactly "play now at this rate".
    func playImmediately(atRate rate: Float) {
        self.rate = rate
    }

    /// iOS 10's stall-avoidance toggle has no pre-10 equivalent; AVPlayer
    /// always behaved as though it were false.
    var automaticallyWaitsToMinimizeStalling: Bool {
        get { false }
        set {}
    }
}

/// Not named `AVPlayer.TimeControlStatus`: the SDK already declares that nested
/// name, and a same-named shadow makes lookup inside AVPlayer ambiguous. Call
/// sites only ever write `.playing` and friends, so the spelling never reaches
/// them.
enum LegacyTimeControlStatus: Int {
    case paused, waitingToPlayAtSpecifiedRate, playing
}

extension AVPlayerItem {
    /// iOS 10 buffering hint. No pre-10 control exists; accepted and ignored.
    var preferredForwardBufferDuration: TimeInterval {
        get { 0 }
        set {}
    }
}

extension AVAudioSession {
    /// The combined form is iOS 10; the two-call form is iOS 6 and equivalent.
    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions = []
    ) throws {
        try setCategory(category, options: options)
        try setMode(mode)
    }
}

extension MPRemoteCommandCenter {
    /// iOS 9.1. Present on every A5 device that reaches 9.3.5, so this only
    /// exists for a 9.0 deployment target and is otherwise the real command.
    var changePlaybackPositionCommand: MPRemoteCommand {
        skipForwardCommand
    }
}

/// `MPNowPlayingInfoPropertyMediaType` and its enum are iOS 10. The key is a
/// plain string, and the raw value is what gets stored.
let MPNowPlayingInfoPropertyMediaType = "MPNowPlayingInfoPropertyMediaType"

enum MPNowPlayingInfoMediaType: UInt {
    case none = 0, audio = 1, video = 2
}

extension MPMediaItemArtwork {
    /// iOS 10's lazy form. iOS 9 has only `init(image:)`, so the handler is
    /// called once, up front, at the size asked for.
    convenience init(
        boundsSize: CGSize,
        requestHandler: @escaping (CGSize) -> UIImage
    ) {
        self.init(image: requestHandler(boundsSize))
    }
}

// MARK: - iOS 17 — present in the source behind #available, stubbed to compile

enum LegacyBackgroundPlaybackPolicy: Int {
    case automatic, continuesIfPossible, pauses
}

extension AVPlayer {
    var audiovisualBackgroundPlaybackPolicy: LegacyBackgroundPlaybackPolicy {
        get { .automatic }
        set {}
    }
}

/// iOS 17 VideoToolbox constant, referenced by the AV1 capability query. No A5X
/// decodes AV1 in any case, so the query answers "no" whichever way it is asked.
let kCMVideoCodecType_AV1: CMVideoCodecType = 0x6176_3031
#endif
