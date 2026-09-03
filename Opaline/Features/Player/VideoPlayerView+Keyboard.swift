import AVFoundation
import UIKit

/// Keyboard transport, expressed in terms of what the player already does.
///
/// Nothing here reimplements playback. Seeking in particular goes through the
/// existing burst seek rather than issuing its own `player.seek`: that code
/// chains each step off the *requested* target rather than the current
/// playhead, which is what makes a fast run of presses add up instead of
/// collapsing into one (seeks are async, so `currentTime()` still reports the
/// old position when presses arrive faster than a seek completes).
extension VideoPlayerView {
    private static let volumeStep: Float = 0.1
    private static let speedStep: Float = 0.25
    /// j / l: one flat step, no escalation. Passing the cap as well as the
    /// ladder is what makes it flat — the burst would otherwise climb to the
    /// touch cap on the second press.
    private static let fixedSeekStep: Double = 10

    func keyboardSeek(forward: Bool, escalating: Bool) {
        let direction = forward ? 1 : -1
        if escalating {
            seek(direction: direction, ladder: Self.keyboardStepLadder)
        } else {
            seek(
                direction: direction,
                ladder: [Self.fixedSeekStep],
                cap: Self.fixedSeekStep
            )
        }
        flashSeekZone(forward ? .forward : .rewind)
        KeyboardDiagnostics.logTimed(
            "seek \(forward ? "fwd" : "back") escalating=\(escalating) " +
            "burst=\(seekBurst.tapCount)"
        )
    }

    func keyboardAdjustVolume(up: Bool) {
        guard let player = player else {
            return
        }
        // Snap to the step rather than accumulating: repeatedly adding 0.1 to a
        // Float drifts (measured on device: 0.8 became 0.79999995, 0.4 became
        // 0.39999992). The HUD rounds, so it looks right while the stored value
        // quietly diverges.
        let raw = player.volume + (up ? Self.volumeStep : -Self.volumeStep)
        let stepped = (raw / Self.volumeStep).rounded() * Self.volumeStep
        let next = min(max(stepped, 0), 1)
        player.volume = next
        showHUD(text: "  \(Int((next * 100).rounded()))%  ")
        hideHUD(after: 0.8)
        KeyboardDiagnostics.logTimed("volume \(next)")
    }

    func keyboardToggleMute() {
        guard let player = player else {
            return
        }
        player.isMuted = !player.isMuted
        showHUD(text: player.isMuted ? "  ✕  " : "  ♪  ")
        hideHUD(after: 0.8)
        KeyboardDiagnostics.logTimed("mute=\(player.isMuted)")
    }

    /// 0-9 jump to that tenth of the video. Zero tolerance so the frame that
    /// arrives is the one the number asked for.
    func keyboardScrub(toTenth tenth: Int) {
        guard let player = player, duration > 0 else {
            return
        }
        let fraction = min(max(Double(tenth) / 10, 0), 1)
        let target = CMTime(
            seconds: duration * fraction,
            preferredTimescale: 600
        )
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        setControls(visible: true, animated: true)
        scheduleAutoHide()
        KeyboardDiagnostics.logTimed("scrub to \(tenth)0%")
    }

    func keyboardNudgeSpeed(faster: Bool) {
        let proposed = playbackSpeed + (faster ? Self.speedStep : -Self.speedStep)
        let snapped = snapToSteps(proposed)
        playbackSpeed = snapped
        player?.rate = player?.rate ?? 0 > 0 ? snapped : 0
        showHUD(text: "  " + String(format: "%.2g", snapped) + "x  ")
        hideHUD(after: 0.8)
        KeyboardDiagnostics.logTimed("speed \(snapped)")
    }
}
