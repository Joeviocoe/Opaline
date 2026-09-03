import UIKit

/// Keeps *something* holding first-responder status, so key commands keep
/// arriving.
///
/// Nothing in the app opted into the responder chain before this branch, and
/// UIKit is inconsistent about consulting `keyCommands` when there is no first
/// responder at all. Rather than rely on that, there is always an explicit one:
/// the focus ring of the visible list when there is one, the watch screen while
/// the player is expanded, and the window root as a floor under both.
///
/// The awkward case is the player collapsing to the mini bar. That does not
/// remove any view from the window — it only applies a transform — so no
/// `didMoveToWindow` fires and the ring would never take the chain back.
final class KeyboardFocusCoordinator {
    static let shared = KeyboardFocusCoordinator()

    private weak var root: UIViewController?
    private weak var activeRing: UIView?
    /// A screen that takes the chain without a ring -- Shorts. Without this,
    /// collapsing the player while on Shorts hands the chain to the window
    /// root and its paging keys go dead until it is re-shown.
    private weak var ringlessResponder: UIViewController?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(self.reassert),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(self.reassert),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func install(root viewController: UIViewController) {
        root = viewController
        reassert()
    }

    func ringlessDidAppear(_ responder: UIViewController) {
        ringlessResponder = responder
    }

    func ringDidEnterWindow(_ ring: UIView) {
        activeRing = ring
    }

    func ringDidLeaveWindow(_ ring: UIView) {
        if activeRing === ring {
            activeRing = nil
        }
    }

    /// `expand(animated:)` runs before the panel's view is in the window, and a
    /// view controller whose view has no window cannot become first responder —
    /// measured on device: this returns NO every time when called inline. The
    /// player's commands still worked, because the chain reaches the watch
    /// screen once something inside it takes focus, but that is luck rather
    /// than design. Retry after the transition so the handoff is deterministic.
    func playerDidExpand(_ watch: UIViewController) {
        let accepted = watch.becomeFirstResponder()
        KeyboardDiagnostics.logResponder(
            "player expand becomeFirstResponder",
            watch,
            accepted: accepted
        )
        guard !accepted else {
            return
        }
        DispatchQueue.main.async { [weak watch] in
            guard let watch = watch, watch.viewIfLoaded?.window != nil else {
                KeyboardDiagnostics.log("player expand retry skipped: no window")
                return
            }
            let retried = watch.becomeFirstResponder()
            KeyboardDiagnostics.logResponder(
                "player expand retry",
                watch,
                accepted: retried
            )
        }
    }

    func playerDidCollapse(_ watch: UIViewController) {
        watch.resignFirstResponder()
        KeyboardDiagnostics.log("player collapsed, returning the chain")
        reassert()
    }

    /// Give the chain back to the ring if one is on screen, otherwise to the
    /// window root. A plain view or view controller becoming first responder
    /// does not raise the software keyboard — only `UIKeyInput` conformers do.
    @objc
    func reassert() {
        guard !KeyboardInputMonitor.shared.isEditingText else {
            KeyboardDiagnostics.log("reassert skipped: a text field is editing")
            return
        }
        if let ring = activeRing, ring.window != nil {
            let accepted = ring.becomeFirstResponder()
            KeyboardDiagnostics.logResponder("reassert ring", ring, accepted: accepted)
            if accepted {
                return
            }
        }
        if let ringless = ringlessResponder, ringless.viewIfLoaded?.window != nil {
            let took = ringless.becomeFirstResponder()
            KeyboardDiagnostics.logResponder("reassert ringless", ringless, accepted: took)
            if took {
                return
            }
        }
        guard let root = root else {
            return
        }
        let accepted = root.becomeFirstResponder()
        KeyboardDiagnostics.logResponder("reassert root", root, accepted: accepted)
    }
}
