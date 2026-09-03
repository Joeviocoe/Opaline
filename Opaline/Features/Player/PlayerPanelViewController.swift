// swiftlint:disable file_length
import UIKit

final class PlayerPanelViewController: UIViewController, UIGestureRecognizerDelegate {
    let watchVC: WatchViewController
    private let navigationWrapper: RotatingNavigationController
    private lazy var expandedPanGesture: UIPanGestureRecognizer = makeExpandedPanGesture()
    private lazy var miniPanGesture: UIPanGestureRecognizer = makeMiniPanGesture()
    // Covers the status-bar area above the nav wrapper so the background
    // colour matches the navigation bar instead of showing through.
    private let statusBarBackdrop = UIView()
    // Top constraint for navigationWrapper; updated to window.safeAreaInsets.top
    // so the nav bar always starts below the status bar / Dynamic Island.
    private var navWrapperTopConstraint: NSLayoutConstraint?

    private(set) var isExpanded = true
    weak var miniBar: MiniPlayerBar? {
        didSet {
            oldValue?.removeGestureRecognizer(miniPanGesture)
            configureMiniBar()
        }
    }
    var onClose: (() -> Void)?
    /// The tab bar controller whose view hosts this panel. Not `parent` — the
    /// panel is parented to the root container instead (issue #30).
    weak var owner: MainTabBarController?

    init(watchVC: WatchViewController) {
        self.watchVC = watchVC
        navigationWrapper = RotatingNavigationController(rootViewController: watchVC)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        installNavigationWrapper()
        view.addGestureRecognizer(expandedPanGesture)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavWrapperTop()
        view.transform = isExpanded ? .identity : collapsedTransform()
    }

    /// `onExpanded` fires once the panel has actually finished expanding —
    /// not when this call returns. A caller that needs to collapse it right
    /// back (q on an empty queue, replicating "tap to play, then tap
    /// minimize") has to wait for that: firing collapse in the same call
    /// stack as expand raced its first-responder handoff, which is the bug
    /// `installPlayerPanel`'s old `startsExpanded` flag existed to dodge.
    func expand(animated: Bool, onExpanded: (() -> Void)? = nil) {
        isExpanded = true
        KeyboardFocusCoordinator.shared.playerDidExpand(watchVC)
        // Expanding is what hands the orientation over to the player — every
        // video after the first reuses this panel, so this, not the watch
        // screen's init, is the moment to keep the orientation it opened in.
        watchVC.keepOpeningOrientation()
        refreshSupportedOrientations()
        refreshMiniBar()
        let animations = {
            self.view.transform = .identity
            self.miniBar?.alpha = 0
            self.miniBar?.transform = .identity
        }
        let completion: (Bool) -> Void = { _ in
            self.miniBar?.isHidden = true
            onExpanded?()
        }
        if animated {
            miniBar?.isHidden = false
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseOut],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

    func collapse(animated: Bool) {
        isExpanded = false
        // Collapsing to the mini bar only applies a transform — nothing
        // leaves the window — so no `didMoveToWindow` fires and the focus
        // ring would never take the responder chain back on its own.
        KeyboardFocusCoordinator.shared.playerDidCollapse(watchVC)
        refreshSupportedOrientations()
        refreshMiniBar()
        miniBar?.transform = .identity
        miniBar?.alpha = 0
        miniBar?.isHidden = false
        let animations = {
            self.view.transform = self.collapsedTransform()
            self.miniBar?.alpha = 1
        }
        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseOut],
                animations: animations,
                completion: nil
            )
        } else {
            animations()
        }
    }

    func close() {
        watchVC.exitFullscreenIfNeeded()
        // Mark it as a user pause *before* pausing. A raw pause is read by the
        // multitasking heuristic as a stolen audio route, and it resumes half a
        // second later — on a player whose panel is by then gone. Observed on
        // device: "paused while active — multitasking, resuming", followed by
        // the loopback server still serving audio with no panel to reach it,
        // and only the media keys able to touch it.
        watchVC.videoPlayerView?.multitaskPause.lastUserPause = CACurrentMediaTime()
        // A pause alone leaves the AVPlayer and its MPRemoteCommandCenter
        // targets alive, so a media key could still resume what this just
        // closed. resetPlaybackSurfaces() detaches it (player = nil) and
        // ends the Now Playing session -- nothing left to act on.
        watchVC.resetPlaybackSurfaces()
        // Removing the panel's view resigns first responder implicitly but
        // never reasserts one -- the ring stayed visibly on its cell with
        // every arrow key dead until switching tabs incidentally fixed it.
        KeyboardFocusCoordinator.shared.playerDidCollapse(watchVC)
        // Closing the player ends the queue with it — otherwise reopening the
        // same mix later picked it up mid-list, shuffle state and all.
        PlaybackQueue.shared.clear()
        miniBar?.layer.removeAllAnimations()
        miniBar?.transform = .identity
        guard let tabBarController = owner else {
            onClose?()
            return
        }
        tabBarController.removePlayerPanel(self)
        onClose?()
    }

    func refreshMiniBar() {
        let player = watchVC.videoPlayerView?.player
        let isPlaying = (player?.rate ?? 0) != 0
        miniBar?.update(
            title: watchVC.initialVideo.title,
            channel: watchVC.initialVideo.channelName,
            isPlaying: isPlaying,
            thumbnailURL: watchVC.initialVideo.thumbnailURL
        )
        miniBar?.attachPlayer(player)
        miniBar?.applyTheme()
    }
}

private extension PlayerPanelViewController {
    /// UITabBarController does not always forward the full status-bar / Dynamic
    /// Island safe-area top to child VCs inserted outside the official
    /// `viewControllers` mechanism.  On iPad (small status bar) this is benign,
    /// but on iPhone the navigation bar ends up at y=0, overlapping the Dynamic
    /// Island.
    ///
    /// Fix: read the window's safeAreaInsets.top (always authoritative) and use
    /// it as the explicit top offset for the navigation wrapper.  A backdrop view
    /// fills the gap with the navigation bar's background colour.
    func updateNavWrapperTop() {
        guard let window = view.window else {
            return
        }
        let top = window.safeAreaInsets.top
        navWrapperTopConstraint?.constant = top
        statusBarBackdrop.backgroundColor = ThemeManager.shared.surface
    }

    func installNavigationWrapper() {
        // Backdrop for the status-bar / Dynamic Island region above the nav bar.
        statusBarBackdrop.translatesAutoresizingMaskIntoConstraints = false
        statusBarBackdrop.backgroundColor = ThemeManager.shared.surface
        view.addSubview(statusBarBackdrop)

        addChild(navigationWrapper)
        navigationWrapper.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationWrapper.view)

        let topConstraint = navigationWrapper.view.topAnchor.constraint(
            equalTo: view.topAnchor,
            constant: 0
        )
        navWrapperTopConstraint = topConstraint

        NSLayoutConstraint.activate([
            statusBarBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            statusBarBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarBackdrop.bottomAnchor.constraint(
                equalTo: navigationWrapper.view.topAnchor
            ),
            topConstraint,
            navigationWrapper.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationWrapper.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationWrapper.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigationWrapper.didMove(toParent: self)
    }

    func configureMiniBar() {
        miniBar?.removeGestureRecognizer(miniPanGesture)
        miniBar?.onClose = { [weak self] in
            self?.close()
        }
        miniBar?.onTap = { [weak self] in
            self?.expand(animated: true)
        }
        miniBar?.addGestureRecognizer(miniPanGesture)
        refreshMiniBar()
    }

    func togglePlayback() {
        guard let player = watchVC.videoPlayerView?.player else {
            return
        }
        if player.rate == 0 {
            player.play()
        } else {
            watchVC.videoPlayerView?
                .multitaskPause.lastUserPause = CACurrentMediaTime()
            player.pause()
        }
        refreshMiniBar()
    }

    func collapsedTransform() -> CGAffineTransform {
        let parentHeight = parent?.view.bounds.height ?? view.bounds.height
        return CGAffineTransform(translationX: 0, y: parentHeight)
    }

    func makeExpandedPanGesture() -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleExpandedPan(_:))
        )
        gesture.delegate = self
        return gesture
    }

    func makeMiniPanGesture() -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleMiniPan(_:))
        )
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }

    func isControlView(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UIControl {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    @objc
    func handleExpandedPan(_ gesture: UIPanGestureRecognizer) {
        guard isExpanded else {
            return
        }
        let translationY = max(0, gesture.translation(in: view).y)
        let velocityY = gesture.velocity(in: view).y
        switch gesture.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: translationY)
        case .ended, .cancelled, .failed:
            if translationY > 120 || velocityY > 600 {
                collapse(animated: true)
            } else {
                expand(animated: true)
            }
        default:
            break
        }
    }

    @objc
    func handleMiniPan(_ gesture: UIPanGestureRecognizer) {
        guard !isExpanded, let miniBar = miniBar else {
            return
        }
        let translationY = max(0, gesture.translation(in: miniBar).y)
        let velocityY = gesture.velocity(in: miniBar).y
        switch gesture.state {
        case .changed:
            miniBar.transform = CGAffineTransform(translationX: 0, y: translationY)
        case .ended, .cancelled, .failed:
            if translationY > 60 || velocityY > 600 {
                close()
            } else {
                UIView.animate(withDuration: 0.2) {
                    miniBar.transform = .identity
                }
            }
        default:
            break
        }
    }
}

extension PlayerPanelViewController {
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === expandedPanGesture {
            guard isExpanded,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer
            else {
                return false
            }
            let velocity = pan.velocity(in: view)
            let location = pan.location(in: view)
            let touchedView = view.hitTest(location, with: nil)
            return abs(velocity.y) > abs(velocity.x)
                && velocity.y > 0
                && !isControlView(touchedView)
        }
        if gestureRecognizer === miniPanGesture {
            guard !isExpanded,
                  let bar = miniBar,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer
            else {
                return false
            }
            let location = pan.location(in: bar)
            let velocity = pan.velocity(in: bar)
            let touchedView = bar.hitTest(location, with: nil)
            return abs(velocity.y) > abs(velocity.x)
                && velocity.y > 0
                && !isControlView(touchedView)
        }
        return true
    }
}

extension PlayerPanelViewController {
    override var childForStatusBarHidden: UIViewController? {
        navigationWrapper
    }

    /// Style goes straight to the watch screen (skipping the nav controller,
    /// which would derive it from its bar style instead of the video state).
    override var childForStatusBarStyle: UIViewController? {
        navigationWrapper.topViewController
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        navigationWrapper
    }

    override var shouldAutorotate: Bool {
        isExpanded ? navigationWrapper.shouldAutorotate : false
    }

    /// Only the expanded player may rotate the app — collapsed to the mini bar
    /// it is just an overlay over the portrait-only tabs.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        isExpanded
            ? navigationWrapper.supportedInterfaceOrientations
            : .portrait
    }

    // Expanding and collapsing swaps the mask above, so both call
    // `refreshSupportedOrientations()` — otherwise the player comes back from
    // the mini bar deaf to rotation until the next unrelated device change.

    @available(iOS 11.0, *)
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateNavWrapperTop()
    }

    @objc
    func handleThemeChange() {
        statusBarBackdrop.backgroundColor = ThemeManager.shared.surface
    }
}
