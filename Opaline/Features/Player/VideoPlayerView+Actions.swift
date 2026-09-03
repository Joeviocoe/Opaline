import AVFoundation
import AVKit
import UIKit

// MARK: - Gesture Handling

extension VideoPlayerView {
    @objc
    func handleTap() {
        if controlsVisible {
            setControls(visible: false, animated: true)
        } else {
            setControls(visible: true, animated: true)
            scheduleAutoHide()
        }
    }

    @objc
    func handleDoubleTap(
        _ gesture: UITapGestureRecognizer
    ) {
        // Straight to the seek, not through the buttons: those now switch
        // videos, and the gesture is the only way to seek by steps.
        let zone = seekZone(atX: gesture.location(in: self).x)
        flashSeekZone(zone)
        switch zone {
        case .rewind:
            seek(direction: -1)
        case .forward:
            seek(direction: 1)
        case .playPause:
            playPauseTapped()
        }
        // The overlay stays as it was: a double tap that pulls it up covers
        // the video the user is seeking through, and on the middle zone it
        // put the controls over a pause the icon already shows (#107).
        if controlsVisible {
            scheduleAutoHide()
        }
    }

    @objc
    func handlePinch(
        _ gesture: UIPinchGestureRecognizer
    ) {
        if isFullscreen {
            handleFullscreenPinch(gesture)
            return
        }
        guard gesture.state == .ended else {
            return
        }
        if gesture.scale > 1.2 {
            delegate?.videoPlayerViewDidTapFullscreen(self)
        }
    }

    @objc
    func handleSwipeDown() {
        guard isFullscreen else {
            return
        }
        delegate?.videoPlayerViewDidTapFullscreen(self)
    }
}

extension CGFloat {
    /// The hidden controls overlay stays a whisper above transparent instead
    /// of fully invisible. At alpha 0 nothing is composited over the video
    /// and the layer is handed to the display's video plane, which bypasses
    /// the accessibility display filters — Reduce White Point, Night Shift
    /// and True Tone stop applying to the picture until an overlay comes
    /// back. Below 0.01 UIKit still skips hit-testing, so taps reach the
    /// player's gestures exactly as before.
    static let hiddenControlsAlpha: CGFloat = 0.005
}

// MARK: - Controls Visibility

extension VideoPlayerView {
    func setControls(visible: Bool, animated: Bool) {
        controlsVisible = visible
        // `updateProgress` skips the seek bar while the overlay is hidden,
        // so catch it up before it comes back into view.
        if visible, let time = player?.currentTime() {
            updateProgress(time: time)
        }
        let targetAlpha: CGFloat = visible ? 1 : .hiddenControlsAlpha
        let animDuration = animated ? 0.2 : 0
        UIView.animate(withDuration: animDuration) {
            self.controlsView.alpha = targetAlpha
            self.topGradientLayer.opacity = visible
                ? 1
                : 0
            self.bottomGradientLayer.opacity = visible
                ? 1
                : 0
        }
        if !visible {
            speedOverlay.isHidden = true
        }
    }

    func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.player?.rate ?? 0 > 0
            else {
                return
            }
            self.setControls(
                visible: false,
                animated: true
            )
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 3,
            execute: item
        )
    }

    func pauseAutoHide() {
        hideWorkItem?.cancel()
    }
}

// MARK: - Button Actions

extension VideoPlayerView {
    @objc
    func playPauseTapped() {
        guard let player = player else {
            return
        }
        if isAtEnd {
            replay()
            return
        }
        if player.rate > 0 {
            multitaskPause.lastUserPause = CACurrentMediaTime()
            player.pause()
        } else {
            player.play()
        }
        scheduleAutoHide()
    }

    // Seeking lives on the double-tap gesture, as in the official app.
    @objc
    func rewindTapped() {
        if hasPreviousVideo { onPrevious?() }
    }

    @objc
    func forwardTapped() {
        onNext?()
    }

    @objc
    func skipButtonTapped() {
        onSkipTapped?()
    }

    @objc
    func settingsTapped() {
        delegate?.videoPlayerViewDidTapSettings(self)
        scheduleAutoHide()
    }

    @objc
    func fullscreenTapped() {
        delegate?.videoPlayerViewDidTapFullscreen(self)
    }
}

// MARK: - Icon Updates

extension VideoPlayerView {
    func updatePlayPauseIcon() {
        if isAtEnd {
            playPauseButton.setImage(PlayerIcons.replay(), for: .normal)
            return
        }
        let isPlaying = (player?.rate ?? 0) > 0
        let icon = isPlaying
            ? PlayerIcons.pause()
            : PlayerIcons.play()
        playPauseButton.setImage(icon, for: .normal)
    }

    func updateFullscreenIcon() {
        fullscreenButton.setImage(
            PlayerIcons.fullscreen(
                isFullscreen: isFullscreen
            ),
            for: .normal
        )
    }
}
