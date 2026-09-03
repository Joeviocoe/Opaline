import AVFoundation
import CoreMedia
import UIKit

// The accelerating seek, moved out of `+Actions` when the keyboard began
// sharing it: that file was within a few lines of the 300-line limit, and
// this is a self-contained concern — which is how the rest of the player is
// organised anyway (`+Speed`, `+Zoom`, `+SeekZones`, and twenty more).

/// Tracks a burst of consecutive same-direction seek taps.
final class SeekBurstState {
    var direction = 0
    var tapCount = 0
    var accumulated: Double = 0
    var lastTap: CFTimeInterval = 0
    /// Position the last tap of this burst asked for. Seeks are async, so
    /// `player.currentTime()` still reports the old playhead when taps come
    /// faster than a seek completes — chaining off the requested target
    /// instead is what makes a burst actually add up.
    var target: CMTime = .invalid
}

// MARK: - Accelerating Seek
//
// Consecutive same-direction taps within `seekBurstWindow` (1.2s — longer
// than a normal tap cadence, short enough that it never spans two separate
// seek intents) accumulate into a growing step. The per-tap ladder is
// 10 / 20 / 30s for the first three taps of a burst (so 3 taps ≈ 60s,
// matching "roughly 3-4 taps get you about a minute"), then flat 60s per
// tap after that — capped so a long hold-on burst stays fast but
// controllable rather than exploding. An opposite-direction tap, or one
// that arrives after the window has elapsed, resets the burst.
extension VideoPlayerView {
    private static let seekBurstWindow: CFTimeInterval = 1.2
    /// Below this, a repeat is the keyboard auto-repeating, not a person.
    /// Measured repeat interval on the iPad 3 is ~103ms; a human double-tap
    /// runs 150ms and up.
    static let repeatFloor: CFTimeInterval = 0.13
    static let seekStepLadder: [Double] = [10, 20, 30]
    static let seekStepCap: Double = 60
    /// The keyboard's own ladder. An arrow tap should be a finer nudge than a
    /// tap on the screen, but repeats escalate through this same burst — which
    /// is also what lets a key press and a screen tap accumulate together
    /// instead of fighting over the burst state.
    static let keyboardStepLadder: [Double] = [5, 10, 30]

    /// A press in the same direction inside the window extends the burst;
    /// anything else starts a new one.
    ///
    /// `repeatFloor` is what stops a *held* key from climbing the ladder. On
    /// iOS 9 a UIKeyCommand carries no press phase, so auto-repeat and tapping
    /// are the same event — measured on the iPad 3: ~400ms to the first repeat,
    /// then ~103ms, about ten a second. Left to escalate, one second of holding
    /// seeks about eight minutes. Anything arriving faster than a person taps
    /// therefore repeats the current step instead of advancing it, so holding
    /// scrubs at a steady rate and deliberate taps still escalate.
    ///
    /// The two cadences do overlap at the edges — an observed tap came in at
    /// 104ms — so a very fast tapper gets flat steps. That is the harmless
    /// direction to be wrong in: it degrades to what a single tap already does.
    private func advanceBurst(direction: Int) {
        let now = CACurrentMediaTime()
        let gap = now - seekBurst.lastTap
        if direction == seekBurst.direction, gap < Self.repeatFloor {
            seekBurst.lastTap = now
            return
        }
        if direction == seekBurst.direction,
           now - seekBurst.lastTap < Self.seekBurstWindow {
            seekBurst.tapCount += 1
        } else {
            seekBurst.direction = direction
            seekBurst.tapCount = 1
            seekBurst.accumulated = 0
            seekBurst.target = .invalid
        }
        seekBurst.lastTap = now
    }

    private func seekStep(forTapIndex index: Int, ladder: [Double], cap: Double) -> Double {
        if index >= 1, index <= ladder.count {
            return ladder[index - 1]
        }
        return cap
    }

    func seek(
        direction: Int,
        ladder: [Double] = VideoPlayerView.seekStepLadder,
        cap: Double = VideoPlayerView.seekStepCap
    ) {
        guard let player = player else {
            return
        }
        advanceBurst(direction: direction)
        let step = seekStep(forTapIndex: seekBurst.tapCount, ladder: ladder, cap: cap)
        seekBurst.accumulated += step

        let offset = CMTime(seconds: step, preferredTimescale: 600)
        let base = seekBurst.target.isNumeric
            ? seekBurst.target
            : player.currentTime()
        let proposed = direction > 0 ? base + offset : base - offset
        let destination = clampedSeekTime(proposed)
        seekBurst.target = destination
        player.seek(
            to: destination,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        showSeekHUD(totalOffset: seekBurst.accumulated * Double(direction))
        scheduleAutoHide()
    }

    private func clampedSeekTime(_ time: CMTime) -> CMTime {
        if time < .zero {
            return .zero
        }
        if duration > 0 {
            let end = CMTime(seconds: duration, preferredTimescale: 600)
            if time > end {
                return end
            }
        }
        return time
    }

    /// Shows how far the burst has moved, centered, *and* where it lands,
    /// trailing. The seek bar is hidden while seeking from the keyboard, so
    /// without the destination there is nothing on screen saying where you
    /// are -- two separate labels rather than one combined string, because
    /// "centered" and "right-aligned" cannot both be true of one UILabel.
    private func showSeekHUD(totalOffset: Double) {
        let sign = totalOffset >= 0 ? "+" : "-"
        let magnitude = abs(totalOffset)
        let offsetText: String
        if magnitude < 60 {
            // Under a minute keep the localized "+15s" form.
            offsetText = "player.seek.offset".localized(
                with: "\(sign)\(Int(magnitude.rounded()))"
            )
        } else {
            offsetText = sign + Self.clockString(magnitude)
        }
        showHUD(text: "  \(offsetText)  ")
        let landing = seekBurst.target.isNumeric
            ? seekBurst.target.seconds
            : (player?.currentTime().seconds ?? 0)
        showPositionHUD(
            text: "  \(Self.clockString(landing)) / \(Self.clockString(duration))  "
        )
        hideHUD(after: 0.8)
    }

    /// m:ss, or h:mm:ss once there is an hour to show.
    static func clockString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
