import AVKit
import UIKit

// MARK: - Picture in Picture

extension VideoPlayerView {
    /// Device support. The button is offered whenever the hardware allows it,
    /// regardless of the setting — the setting only governs *automatic* PiP.
    var isPiPAvailable: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isPiPActive: Bool {
        pipIsStarting || pipController?.isPictureInPictureActive == true
    }

    /// User setting: leaving the app puts the video in PiP (on) or keeps
    /// audio-only background playback (off). Manual PiP always works.
    var isAutoPiPEnabled: Bool {
        UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Player.pipEnabled
        ) as? Bool ?? true
    }

    /// Whether the system will start PiP by itself during the background
    /// transition — the layer must keep its player for that to work.
    ///
    /// AVKit has always done this for fullscreen playback;
    /// `canStartPictureInPictureAutomaticallyFromInline` (iOS 14.2) is what
    /// extends it to inline. Below that, inline gets background audio and the
    /// PiP button — starting PiP by hand is not an option, because the last
    /// callback before the transition is `willResignActive`, which Control
    /// Center and the notification shade raise just as loudly, and a start
    /// issued once the app is in the background is swallowed by AVKit without
    /// even a `failedToStart`.
    private var willAutoPiP: Bool {
        guard isAutoPiPEnabled, isPiPAvailable else {
            return false
        }
        if #available(iOS 14.2, *) {
            return true
        }
        return isFullscreen
    }

    /// Hands the current item to a replacement player and re-points every
    /// observer at it. Used to escape the iOS 12 state where a player that
    /// was detached from its layer can never enter PiP again (#28).
    func replacePlayer(_ newPlayer: AVPlayer) {
        removePeriodicObserver()
        removePlayerObservers()
        player = newPlayer
        playerLayer.player = newPlayer
        pipController = nil
        addPeriodicObserver()
        addPlayerObservers()
        setupPiP()
        updatePlayPauseIcon()
    }

    func setupPiP() {
        setControlAvailability(
            pipButton,
            available: isPiPAvailable
        )
        guard isPiPAvailable else {
            return
        }
        if pipController == nil {
            pipController = AVPictureInPictureController(
                playerLayer: playerLayer
            )
            pipController?.delegate = self
        }
        if #available(iOS 14.2, *) {
            pipController?
                .canStartPictureInPictureAutomaticallyFromInline = isAutoPiPEnabled
        }
    }

    /// Control Center / Notification Center peeks fire this without ever
    /// backgrounding the app, so nothing is torn down here — only the
    /// play state is remembered for the background resume.
    @objc
    func appWillResignActive() {
        guard !isPiPActive else {
            return
        }
        wasPlayingOnResign = (player?.rate ?? 0) > 0
        // The setting can be toggled without ever leaving the app, so the
        // system flag is refreshed here rather than only in `setupPiP()`.
        //
        // From iOS 26 the flag is advisory: with Settings → General → Picture
        // in Picture → Start PiP Automatically on, the system opens the window
        // regardless. Both ways around it were tried on device and are worse
        // than obeying — dropping the controller works only until the first
        // manual PiP (AVKit keeps it alive past our reference and starts that
        // ghost with no delegate to hear it), and closing the window from
        // `didStart` leaves it flashing open and shut on every app switch.
        if #available(iOS 14.2, *) {
            pipController?
                .canStartPictureInPictureAutomaticallyFromInline = isAutoPiPEnabled
        }
    }

    /// A real backgrounding: detach the layer (a layer-backed player is paused
    /// by iOS in the background) and resume audio. Deferred one tick because
    /// auto-PiP may still be starting and would lose its player.
    ///
    /// The detach is skipped whenever PiP is expected to take over: on iOS 12
    /// it permanently breaks PiP for this player — every later start fails
    /// with AVKitErrorDomain -1001, and neither a fresh controller nor a fresh
    /// layer revives it, only a new player (i.e. another video).
    @objc
    func appDidEnterBackground() {
        guard BackgroundPlaybackService.isEnabled else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.enterBackgroundAudioMode()
        }
    }

    private func enterBackgroundAudioMode(force: Bool = false) {
        // iOS 15+ keeps background audio alive through
        // `audiovisualBackgroundPlaybackPolicy`, so the layer never has to
        // give up its player — and PiP survives, lock screen included.
        if #available(iOS 15.0, *) {
            return
        }
        guard !isPiPActive else {
            return
        }
        // Waiting on the system's own auto-PiP: the layer has to keep its
        // player for that, so the audio fallback is held back until AVKit has
        // had its chance. It gets one second — a layer-backed player that is
        // neither in PiP nor detached is paused by iOS soon after (#31).
        if willAutoPiP, !force {
            pipTrace("auto: waiting for the system")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.isPiPActive else {
                    return
                }
                self.pipTrace("auto: system did not start, audio only")
                self.enterBackgroundAudioMode(force: true)
            }
            return
        }
        playerLayer.player = nil
        playerNeedsRebuildForPiP = true
        if wasPlayingOnResign, let player, player.rate == 0 {
            player.play()
        }
    }

    @objc
    func appDidBecomeActive() {
        guard let player else {
            return
        }
        // While PiP runs, AVKit owns the player — rebinding it to the layer
        // here yanks it back and drops playback into a paused state.
        if playerLayer.player == nil, !isPiPActive {
            playerLayer.player = player
        }
        // We are the frontmost app again: undo the multitasking pause.
        if multitaskPause.systemPaused, !isPiPActive {
            multitaskPause.systemPaused = false
            if player.rate == 0 {
                player.play()
            }
        }
        // Re-evaluate the PiP setting (it may have changed in Settings).
        setupPiP()
        rebuildPlayerIfPoisoned()
    }

    /// The background detach costs this player its ability to enter PiP on
    /// iOS 12, so it is swapped out here rather than at the moment PiP is
    /// asked for — a fresh controller needs a beat to report itself usable.
    private func rebuildPlayerIfPoisoned() {
        // Matches the detach in `enterBackgroundAudioMode()`: everything below
        // iOS 15 still loses its layer to keep audio alive, and thus needs the
        // swap — including 14.2–14.x, where auto-PiP already works.
        if #available(iOS 15.0, *) {
            return
        }
        guard playerNeedsRebuildForPiP, !isPiPActive, isAutoPiPEnabled else {
            return
        }
        playerNeedsRebuildForPiP = false
        onNeedsFreshPlayer?()
    }

    @objc
    func pipTapped() {
        pipTrace("tap")
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
            return
        }
        // With auto-PiP off nothing rebuilds the player on foregrounding, so
        // a background-audio session leaves it unable to enter PiP. Pay that
        // cost here instead — only when PiP is actually asked for.
        if playerNeedsRebuildForPiP {
            playerNeedsRebuildForPiP = false
            onNeedsFreshPlayer?()
        }
        startPiPWhenPossible()
    }

    /// A just-rebuilt player needs a moment before AVKit accepts a start, and
    /// that wait covers the fresh item's buffering — hence the generous
    /// budget. Polling because `isPictureInPicturePossible` is not KVO-safe
    /// to observe from an extension without extra stored state.
    private func startPiPWhenPossible(attempt: Int = 0) {
        guard let pip = pipController, !pip.isPictureInPictureActive else {
            return
        }
        guard attempt < 60 else {
            pipTrace("wait: gave up")
            return
        }
        // `isPictureInPicturePossible` turns true before the rebuilt layer has
        // drawn its first frame, and a start in that window is swallowed
        // without a single delegate callback — wait for the picture as well.
        guard pip.isPictureInPicturePossible, playerLayer.isReadyForDisplay else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startPiPWhenPossible(attempt: attempt + 1)
            }
            return
        }
        pip.startPictureInPicture()
    }
}
