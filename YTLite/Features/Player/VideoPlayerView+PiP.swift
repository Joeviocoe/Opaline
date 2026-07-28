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
        if #available(iOS 14.2, *) {
            pipController?
                .canStartPictureInPictureAutomaticallyFromInline = isAutoPiPEnabled
        }
        // iOS 26 starts PiP on backgrounding even with the flag set to false,
        // so the controller itself is taken away for the transition and
        // rebuilt on activation — the button keeps working, nothing can
        // auto-start. Safe from iOS 15 on, where the layer is never detached
        // and a rebuilt controller therefore stays usable.
        if #available(iOS 15.0, *), !isAutoPiPEnabled {
            pipController = nil
        }
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
        // iOS 15+ keeps background audio alive through
        // `audiovisualBackgroundPlaybackPolicy`, so the layer never has to
        // give up its player — and PiP survives, lock screen included.
        if #available(iOS 15.0, *) {
            return
        }
        guard !isPiPActive, !willAutoPiP else {
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
            AppLog.player("PiP: gave up waiting for a usable controller")
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
        // This callback means "put your own player UI back": expand the panel
        // so AVKit hands the picture to a layer that is actually on screen —
        // restoring into a collapsed panel flashes the whole app black.
        // Handing it to a layer without a player stops playback outright.
        wasPlayingOnResign = (player?.rate ?? 0) > 0
        VideoRouter.shared.expandPanel()
        if playerLayer.player == nil {
            playerLayer.player = player
        }
        completionHandler(true)
    }
}
