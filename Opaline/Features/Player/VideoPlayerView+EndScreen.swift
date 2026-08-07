import UIKit

// MARK: - End screen
//
// When a video ends and nothing plays after it, the centre trio stops being
// Back 10s / Play / Forward 10s and becomes Previous / Replay / Next —
// backed by the same handlers as the Control Center transport controls.

extension VideoPlayerView {
    /// Restart from the top. Leaving `isAtEnd` to the periodic observer
    /// would flash the play icon for a tick, so it is cleared here.
    func replay() {
        isAtEnd = false
        player?.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player?.play()
        scheduleAutoHide()
    }

    /// Previous / Next never move; only the middle button changes, and
    /// dead directions are dimmed rather than hidden — the trio's layout is
    /// fixed, and a gap where a button was reads as a glitch.
    func updateCenterIcons() {
        updatePlayPauseIcon()
        setEnabled(rewindButton, hasPreviousVideo)
    }

    private func setEnabled(_ button: UIButton, _ enabled: Bool) {
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.35
    }

    func setCenter(hidden: Bool) {
        playPauseButton.isHidden = hidden
        rewindButton.isHidden = hidden
        forwardButton.isHidden = hidden
    }
}

// MARK: - Icons

extension PlayerIcons {
    static func replay() -> UIImage {
        playerIcon("icon_replay", size: 36)
    }

    static func previous() -> UIImage {
        playerIcon("icon_previous", size: 30)
    }

    static func next() -> UIImage {
        playerIcon("icon_next", size: 30)
    }
}
