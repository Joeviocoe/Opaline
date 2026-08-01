import UIKit

// MARK: - VideoPlayerViewDelegate

extension WatchViewController: VideoPlayerViewDelegate {
    func videoPlayerViewDidTapSettings(
        _ playerView: VideoPlayerView
    ) {
        let stats = "player.menu.stats".localized
        var items = [
            PlayerMenuItem(
                title: "player.menu.quality".localized
            ) { [weak self] in
                self?.showQualityPicker()
            }
        ]
        if playbackFacade.activeVideoSource?
            .supportsAudioTrackSelection == true {
            items.append(
                PlayerMenuItem(
                    title: "player.menu.audioTrack".localized
                ) { [weak self] in
                    self?.showAudioTrackPicker()
                }
            )
        }
        items.append(
            PlayerMenuItem(
                title: statsOverlay != nil ? "✓ \(stats)" : stats
            ) { [weak self] in
                self?.toggleStatsOverlay()
            }
        )
        presentPlayerMenu(
            title: "player.menu.settings".localized, items: items
        )
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
        rotateInterface(to: playerView.isFullscreen ? .portrait : .landscapeRight)
    }

    func enterFullscreen(playerView: VideoPlayerView, animated: Bool = true) {
        guard let window = view.window else {
            return
        }
        detachPlayerToWindow(playerView, window: window)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        guard animated else {
            playerView.frame = window.bounds
            playerView.applyAutoZoomIfNeeded()
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = window.bounds
            },
            completion: { _ in
                playerView.applyAutoZoomIfNeeded()
            }
        )
    }

    private func detachPlayerToWindow(
        _ playerView: VideoPlayerView,
        window: UIWindow
    ) {
        let frameInWindow = playerView.convert(
            playerView.bounds, to: window
        )
        fullscreenSnapshot = (
            superview: playerView.superview ?? view,
            frame: playerView.frame
        )
        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = true
        // Allow the player to resize with the window when the device rotates while
        // in fullscreen, so the video fills the screen in the new orientation.
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.frame = frameInWindow
        window.addSubview(playerView)
        playerView.isFullscreen = true
    }

    func exitFullscreen(playerView: VideoPlayerView, animated: Bool = true) {
        guard let window = view.window,
              let snap = fullscreenSnapshot else {
            return
        }
        let target = snap.superview.convert(snap.frame, to: window)
        guard animated else {
            restoreFromFullscreen(playerView: playerView, snapshot: snap)
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = target
            }, completion: { [weak self] _ in
                self?.restoreFromFullscreen(playerView: playerView, snapshot: snap)
            }
        )
    }

    func restoreFromFullscreen(
        playerView: VideoPlayerView,
        snapshot: (superview: UIView, frame: CGRect)
    ) {
        playerView.removeFromSuperview()
        let sv = snapshot.superview
        playerView.transform = .identity
        playerView.bounds = CGRect(origin: .zero, size: snapshot.frame.size)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.autoresizingMask = []
        sv.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: sv.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: sv.bottomAnchor)
        ])
        playerView.isFullscreen = false
        fullscreenSnapshot = nil
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        updateLayoutForSize()
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
        videoPlayerView?.isFullscreen == true
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
        let released = lock == .landscape
            ? device.isLandscape || device == .portraitUpsideDown
            : !device.isLandscape
        guard released else {
            return
        }
        orientationLock = nil
        // Widening the mask back is invisible to UIKit until it re-reads it —
        // without this the interface stays pinned to what the lock allowed.
        refreshSupportedOrientations()
    }
}
