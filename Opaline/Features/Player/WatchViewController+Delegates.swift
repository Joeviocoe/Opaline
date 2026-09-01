import UIKit

// MARK: - VideoPlayerViewDelegate

extension WatchViewController: VideoPlayerViewDelegate {
    func videoPlayerViewDidTapSettings(
        _ playerView: VideoPlayerView
    ) {
        presentPlayerMenu(
            title: "player.menu.settings".localized,
            items: playbackSettingsItems()
        )
    }

    private func menuItem(
        _ title: String,
        action: @escaping (WatchViewController) -> Void
    ) -> PlayerMenuItem {
        PlayerMenuItem(title: title) { [weak self] in
            guard let self = self else {
                return
            }
            action(self)
        }
    }

    private func playbackSettingsItems() -> [PlayerMenuItem] {
        let stats = "player.menu.stats".localized
        var items = [
            menuItem("player.menu.quality".localized) {
                $0.showQualityPicker()
            }
        ]
        if playbackFacade.activeVideoSource?
            .supportsAudioTrackSelection == true {
            items.append(
                menuItem("player.menu.audioTrack".localized) {
                    $0.showAudioTrackPicker()
                }
            )
        }
        if !queue.videos.isEmpty {
            items.append(
                menuItem("player.menu.queue".localized) {
                    $0.showQueue()
                }
            )
        }
        items.append(
            menuItem(statsOverlay != nil ? "✓ \(stats)" : stats) {
                $0.toggleStatsOverlay()
            }
        )
        return items
    }

    /// Same switch the quality ladder performs — the button is the shortcut
    /// and the indicator, not a second mechanism.
    func videoPlayerViewDidTapAudioOnly(_ playerView: VideoPlayerView) {
        guard let source = playbackFacade.activeVideoSource else {
            return
        }
        let target = AudioOnlyMode.isEnabled
            ? AudioOnlyMode.videoQuality(in: source.availableQualities)
            : AudioOnlyMode.quality
        guard let target = target else {
            return
        }
        selectSourceQuality(target, source: source)
    }

    func videoPlayerViewDidTapFullscreen(_ playerView: VideoPlayerView) {
        // iPad rotates freely, so fullscreen there is a plain window fill.
        // iPhone is portrait-only outside the player: the button rotates the
        // interface, and the rotation is what enters or leaves fullscreen.
        guard UIDevice.current.userInterfaceIdiom != .pad else {
            if playerView.isFullscreen {
                exitFullscreen(playerView: playerView)
            } else {
                enterFullscreen(playerView: playerView)
            }
            return
        }
        // Normally the two agree and the rotation drives the state. When they
        // have drifted apart — landscape without fullscreen, because the
        // interface got there without a rotation we could ride — asking for a
        // rotation asks for nothing, so fix the state itself instead.
        let isLandscapeNow = view.bounds.width > view.bounds.height
        guard playerView.isFullscreen == isLandscapeNow else {
            syncFullscreenWithRotation(isLandscape: isLandscapeNow)
            return
        }
        rotateInterface(to: playerView.isFullscreen ? .portrait : .landscapeRight)
    }
}

// MARK: - Status bar / home indicator

extension WatchViewController {
    static var hidesStatusBarInFullscreen: Bool {
        UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Player.hideStatusBarInFullscreen
        ) as? Bool ?? true
    }

    var isPlayerFullscreen: Bool {
        videoPlayerView?.isFullscreen == true && !isLeavingFullscreen
    }

    override var prefersStatusBarHidden: Bool {
        isPlayerFullscreen && Self.hidesStatusBarInFullscreen
    }

    /// Over fullscreen video the bar must be light regardless of theme —
    /// `.default` is black-on-black there (looks "hidden", except a charging
    /// battery icon).
    override var preferredStatusBarStyle: UIStatusBarStyle {
        isPlayerFullscreen ? .lightContent : ThemeManager.shared.statusBarStyle
    }

    @available(iOS 11.0, *)
    override var prefersHomeIndicatorAutoHidden: Bool {
        isPlayerFullscreen
    }
}

// MARK: - iPhone rotation-driven fullscreen

extension WatchViewController {
    /// Rotates the whole interface, so the home indicator, notification and
    /// Control Center edges follow the video — a transform inside a portrait
    /// window leaves the system believing the phone is upright.
    func rotateInterface(to orientation: UIInterfaceOrientation) {
        // Read the physical orientation first: the KVC write below overwrites
        // it with the one we are asking for.
        let device = UIDevice.current.orientation
        let mask: UIInterfaceOrientationMask =
            orientation.isLandscape ? .landscape : .portrait
        orientationLock = mask
        orientationLockHeld = nil
        refreshSupportedOrientations()
        if #available(iOS 16.0, *) {
            view.window?.windowScene?.requestGeometryUpdate(
                .iOS(interfaceOrientations: mask)
            )
        } else {
            // KVC on `orientation` is the only pre-iOS 16 way to rotate on demand.
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }
        // The phone may already be held the way we just rotated to — then no
        // orientation notification is coming and the lock would never lift.
        releaseOrientationLock(ifDeviceIs: device)
    }

    /// The tabs are portrait-only, so a phone held sideways shows an upright
    /// feed. Opening a video widens the mask, and UIKit snaps straight into
    /// landscape — into a fullscreen nobody asked for. Opening a video is not a
    /// rotation gesture, so hold the orientation it was opened in until the
    /// phone is turned upright, exactly like the lock a fullscreen exit takes.
    ///
    /// Only when the interface disagrees with the phone: opened from an already
    /// landscape one — iPad, or a video tapped from fullscreen — it must stay.
    func keepOpeningOrientation() {
        guard UIDevice.current.userInterfaceIdiom != .pad,
              HeldOrientation.current.isLandscape,
              UIApplication.shared.statusBarOrientation.isPortrait else {
            return
        }
        orientationLock = .portrait
        orientationLockHeld = HeldOrientation.current
    }

    /// Landscape *is* fullscreen on iPhone, so the rotation drives the state.
    /// Called from inside the rotation transition — the transition animates it.
    func syncFullscreenWithRotation(isLandscape: Bool) {
        guard UIDevice.current.userInterfaceIdiom != .pad,
              let playerView = videoPlayerView,
              playerView.isFullscreen != isLandscape else {
            return
        }
        if isLandscape {
            enterFullscreen(playerView: playerView, animated: false)
        } else {
            exitFullscreen(playerView: playerView, animated: false)
        }
    }

    /// Releases the lock taken by `rotateInterface`, so autorotation resumes.
    ///
    /// The lock exists only to stop UIKit snapping straight back to the way the
    /// phone is physically held, so it lasts exactly as long as that conflict:
    /// tap fullscreen while upright and the interface stays landscape until the
    /// phone moves, then the next return to portrait leaves fullscreen.
    @objc
    func handleDeviceOrientationChange() {
        releaseOrientationLock(ifDeviceIs: UIDevice.current.orientation)
    }

    private func releaseOrientationLock(ifDeviceIs device: UIDeviceOrientation) {
        guard let lock = orientationLock else {
            return
        }
        // Only a real orientation frees a landscape lock. `.faceUp` is one nudge
        // away whenever the phone is held tilted, and treating it as "left
        // portrait" drops out of fullscreen on a 1.5° wobble.
        let released: Bool
        if let held = orientationLockHeld {
            // The opening lock waits on the hand, not on an orientation:
            // turning a phone from one landscape to the other is as deliberate
            // as turning it upright, and the portrait it passes through on the
            // way may never be reported at all.
            released = (device.isPortrait || device.isLandscape) && device != held
        } else if lock == .landscape {
            released = device.isLandscape || device == .portraitUpsideDown
        } else {
            released = !device.isLandscape
        }
        guard released else {
            return
        }
        orientationLock = nil
        orientationLockHeld = nil
        // Widening the mask back is invisible to UIKit until it re-reads it —
        // without this the interface stays pinned to what the lock allowed.
        refreshSupportedOrientations()
    }
}
