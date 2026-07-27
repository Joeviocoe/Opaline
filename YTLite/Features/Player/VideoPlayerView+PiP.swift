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

    /// The screen went dark, i.e. the device is locking rather than switching
    /// to another app — PiP cannot take over behind the lock screen, so
    /// background audio wins. iOS exposes no lock state at all, and this
    /// heuristic would fail on an always-on display; that is safe here
    /// because only `startAutoPiPIfNeeded()` consults it, and that runs
    /// solely below iOS 14.2 — long before always-on hardware existed.
    private var isScreenLocked: Bool {
        UIScreen.main.brightness == 0
    }

    /// Whether the system will start PiP by itself during the background
    /// transition — the layer must keep its player for that to work. Before
    /// iOS 14.2 there is no such automatism; `startAutoPiPIfNeeded()` covers
    /// those versions and the detach then keys off `isPiPActive` instead.
    private var willAutoPiP: Bool {
        guard isAutoPiPEnabled, isPiPAvailable else {
            return false
        }
        if #available(iOS 14.2, *) {
            return true
        }
        return false
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
        startAutoPiPIfNeeded()
    }

    /// Before iOS 14.2 nothing starts PiP automatically, so it is started by
    /// hand — here rather than in `appDidEnterBackground`, because AVKit only
    /// accepts a start while the app is still foreground-active and rejects
    /// anything later with AVKitErrorDomain -1001.
    private func startAutoPiPIfNeeded() {
        if #available(iOS 14.2, *) {
            return
        }
        guard isAutoPiPEnabled, wasPlayingOnResign, !isScreenLocked,
              pipController?.isPictureInPicturePossible == true
        else {
            return
        }
        pipIsStarting = true
        pipController?.startPictureInPicture()
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

    private func enterBackgroundAudioMode() {
        guard !isPiPActive, !willAutoPiP else {
            return
        }
        playerLayer.player = nil
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
        // Re-evaluate the PiP setting (it may have changed in Settings).
        setupPiP()
    }

    @objc
    func pipTapped() {
        guard let pip = pipController else {
            return
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }
}

// MARK: - PiP Delegate

extension VideoPlayerView: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        pipIsStarting = true
        pipButton.setImage(
            PlayerIcons.pipExit(),
            for: .normal
        )
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        pipIsStarting = false
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        pipIsStarting = false
        // AVKit pauses on the way out of PiP; restore what was playing.
        if wasPlayingOnResign, let player, player.rate == 0 {
            player.play()
        }
        pipButton.setImage(
            PlayerIcons.pip(),
            for: .normal
        )
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        AppLog.player("PiP failed to start: \(error)")
        pipIsStarting = false
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
    ) {
        // This callback means "put your own player UI back". Handing the
        // player to a layer that no longer holds it makes AVKit stop
        // playback, so the binding is restored before answering.
        wasPlayingOnResign = (player?.rate ?? 0) > 0
        if playerLayer.player == nil {
            playerLayer.player = player
        }
        completionHandler(true)
    }
}
