import UIKit

/// The watch screen's key handling.
///
/// It takes the responder chain while the player panel is expanded, so its
/// commands shadow the global ones underneath — which is what lets `space` mean
/// "toggle this video" here and "toggle the mini player" everywhere else,
/// without either one knowing about the other.
extension WatchViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        if KeyboardInputMonitor.shared.isEditingText {
            return KeyCommandCatalog.textEntry
        }
        if KeyboardInputMonitor.isPresentingModally(self) {
            return nil
        }
        return KeyCommandCatalog.player
    }

    /// The second input route. `UIPress.key` — the character behind a press —
    /// is iOS 13.4, but `UIPressType` is iOS 9.0 and covers the media keys, so
    /// a keyboard that sends play/pause as a press rather than as an HID
    /// consumer-control usage is served here instead of through
    /// `MPRemoteCommandCenter`. Both routes are live and de-duplicated against
    /// each other; every press type is logged, including ones nothing acts on,
    /// so one device session settles which route a given keyboard uses.
    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {
        var handled = false
        for press in presses {
            KeyboardDiagnostics.logTimed("press \(PressTypeResponder.describe(press))")
            guard press.type == .playPause else {
                continue
            }
            if PressTypeResponder.claimPress(source: "UIPress/watch") {
                keyboardTogglePlayPause()
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}

// MARK: - Transport

extension WatchViewController {
    @objc
    func keyboardTogglePlayPause() {
        videoPlayerView?.playPauseTapped()
    }

    @objc
    func keyboardSeekBack() {
        videoPlayerView?.keyboardSeek(forward: false, escalating: true)
    }

    @objc
    func keyboardSeekForward() {
        videoPlayerView?.keyboardSeek(forward: true, escalating: true)
    }

    @objc
    func keyboardSeekBackFixed() {
        videoPlayerView?.keyboardSeek(forward: false, escalating: false)
    }

    @objc
    func keyboardSeekForwardFixed() {
        videoPlayerView?.keyboardSeek(forward: true, escalating: false)
    }

    @objc
    func keyboardVolumeUp() {
        videoPlayerView?.keyboardAdjustVolume(up: true)
    }

    @objc
    func keyboardVolumeDown() {
        videoPlayerView?.keyboardAdjustVolume(up: false)
    }

    @objc
    func keyboardToggleMute() {
        videoPlayerView?.keyboardToggleMute()
    }

    @objc
    func keyboardToggleFullscreen() {
        guard let playerView = videoPlayerView else {
            return
        }
        videoPlayerViewDidTapFullscreen(playerView)
    }

    @objc
    func keyboardPlayNext() {
        playNextFromRemote()
    }

    @objc
    func keyboardPlayPrevious() {
        previousFromRemote()
    }

    @objc
    func keyboardShowSubtitles() {
        showSubtitlePicker()
    }

    /// Toggle, not just open: pressing the same key again is how anyone
    /// expects to get a panel back off the screen.
    @objc
    func keyboardShowQueue() {
        if presentedSheet == .queue {
            KeyboardDiagnostics.logTimed("queue panel: closing")
            collapseSheet()
            return
        }
        KeyboardDiagnostics.logTimed("queue panel: opening")
        showQueue()
    }

    /// Fullscreen first, then the whole panel — the same order the close
    /// button walks, so escape never skips a level.
    @objc
    func keyboardEscape() {
        KeyboardDiagnostics.logTimed("escape fullscreen=\(isPlayerFullscreen)")
        if isPlayerFullscreen {
            exitFullscreenIfNeeded()
            return
        }
        closeTapped()
    }
}

// MARK: - Media keys vs Control Center

extension WatchViewController {
    /// A keyboard's << and >> arrive as `previousTrackCommand` /
    /// `nextTrackCommand` — the very same commands Control Center, the lock
    /// screen and AirPods send. There is no field on the event naming the
    /// source, so the only thing separating them is *when* they arrive: a
    /// keyboard press reaches a foreground app with the player on screen,
    /// while Control Center and the lock screen are used with the app
    /// backgrounded or the device locked.
    ///
    /// So: seek in the foreground, skip everywhere else. `[` and `]` stay
    /// bound to previous/next unconditionally, so nothing is lost either way.
    ///
    /// The known hole is Control Center pulled down over a playing video —
    /// the app is still active, so its skip buttons would seek. Rare enough
    /// during playback to be the right trade, and it fails toward the
    /// gentler action.
    var isForegroundTransport: Bool {
        UIApplication.shared.applicationState == .active
            && videoPlayerView != nil
    }

    @objc
    func remoteNextTrack() {
        guard isForegroundTransport else {
            KeyboardDiagnostics.logTimed("remote next -> skip (background)")
            playNextFromRemote()
            return
        }
        KeyboardDiagnostics.logTimed("remote next -> seek (foreground)")
        videoPlayerView?.keyboardSeek(forward: true, escalating: true)
    }

    @objc
    func remotePreviousTrack() {
        guard isForegroundTransport else {
            KeyboardDiagnostics.logTimed("remote previous -> skip (background)")
            previousFromRemote()
            return
        }
        KeyboardDiagnostics.logTimed("remote previous -> seek (foreground)")
        videoPlayerView?.keyboardSeek(forward: false, escalating: true)
    }
}
