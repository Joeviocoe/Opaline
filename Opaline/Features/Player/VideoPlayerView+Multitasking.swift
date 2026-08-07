import AVFoundation
import UIKit

/// Bookkeeping for the iPad multitasking pause — see `noteSystemPause`.
final class MultitaskPauseState {
    var systemPaused = false
    var lastUserPause: CFTimeInterval = 0
    var lastResume: CFTimeInterval = 0
    var resumeAttempts = 0
}

extension VideoPlayerView {
    /// The pause AVPlayer performs on reaching the end looks exactly like a
    /// system pause. Resuming there plays nothing and parks the player in
    /// `waitingToPlayAtSpecifiedRate` — a spinner that never clears.
    private var hasPlayedToEnd: Bool {
        guard let item = player?.currentItem,
              item.duration.isNumeric
        else {
            return false
        }
        let remaining = CMTimeGetSeconds(item.duration)
            - CMTimeGetSeconds(item.currentTime())
        return remaining < 0.5
    }

    /// A pause we did not ask for, while the app is on screen and active: iPad
    /// multitasking takes video away from an app the moment it stops being the
    /// frontmost one (dragged into Slide Over beside another app). Nothing
    /// reports it, and playing again right after is accepted — so that is what
    /// happens here, capped at two tries per 10s so we never fight the system.
    func noteSystemPause(rate: Float) {
        if rate > 0 {
            multitaskPause.systemPaused = false
            return
        }
        let now = CACurrentMediaTime()
        guard !isPiPActive,
              !hasPlayedToEnd,
              UIApplication.shared.applicationState == .active,
              now - multitaskPause.lastUserPause > 0.5
        else {
            return
        }
        if now - multitaskPause.lastResume > 10 {
            multitaskPause.resumeAttempts = 0
        }
        guard multitaskPause.resumeAttempts < 2 else {
            return
        }
        multitaskPause.systemPaused = true
        multitaskPause.resumeAttempts += 1
        multitaskPause.lastResume = now
        AppLog.player("paused while active — multitasking, resuming")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.resumeAfterSystemPause()
        }
    }

    private func resumeAfterSystemPause() {
        guard let player, player.rate == 0, !isPiPActive,
              CACurrentMediaTime() - multitaskPause.lastUserPause > 0.5
        else {
            return
        }
        player.play()
    }
}
