import UIKit

/// Hides the top navigation bar while the user scrolls content down
/// and brings it back on scroll up or near the top, so grids and
/// lists get the extra rows of screen height.
///
/// A screen owns one instance, forwards its vertical scroll events to
/// `handleScroll`, and calls `showBars()` whenever the bar must be
/// back (leaving the screen, programmatic scroll-to-top). `onChange`
/// runs inside the same animation so accessory bars (chips, filter
/// rows) can slide away in sync with the navigation bar.
final class TopBarAutoHider {
    /// Runs inside the hide/show animation with the new hidden state.
    var onChange: ((Bool) -> Void)?

    private(set) var isHidden = false

    private weak var owner: UIViewController?
    private var lastOffsetY: CGFloat = 0

    /// True from the moment a toggle starts until the layout it causes has
    /// settled. Hiding the bar changes the scroll view's insets — and UIKit
    /// adjusts the offset to match — so the toggle feeds a scroll event back
    /// into `handleScroll`, which decides the *opposite* way and toggles
    /// again. That is a real livelock, not a theoretical one: caught by
    /// spindump on an iPad 3 with the main thread at 98.8% CPU, cycling
    /// `scrollViewDidScroll -> setHidden -> setNavigationBarHidden -> layout`
    /// for a solid minute before it broke out on its own.
    private var isToggling = false
    /// When the last toggle ran, so an oscillation cannot run free even if a
    /// re-entrant path is missed.
    private var lastToggleAt: CFTimeInterval = 0
    /// Comfortably longer than the 0.22s bar animation below, so a toggle and
    /// the layout it provokes are always finished before another can start.
    private static let minimumToggleInterval: CFTimeInterval = 0.35

    init(owner: UIViewController) {
        self.owner = owner
    }

    func handleScroll(_ scrollView: UIScrollView) {
        // Everything that moves while a toggle settles is UIKit's doing, not
        // the user's. Track the offset so the next real gesture measures from
        // where the content actually is, but decide nothing from it.
        guard !isToggling else {
            lastOffsetY = scrollView.contentOffset.y
            return
        }
        // Deltas use the raw offset, not the inset-adjusted position:
        // hiding the bar shrinks adjustedContentInset, which would
        // read as a fake scroll-up and pop the bar right back out.
        let y = scrollView.contentOffset.y
        let delta = y - lastOffsetY
        defer {
            lastOffsetY = y
        }
        let fromTop = y + scrollView.adjustedContentInset.top
        // The delta conditions keep the top/bottom rubber-band
        // bounce-backs from toggling the bar.
        if fromTop <= 8, delta <= 0 {
            setHidden(false)
        } else if delta > 4, fromTop > 8, canScroll(scrollView) {
            setHidden(true)
        } else if delta < -4, y < bottomOffsetY(scrollView) {
            setHidden(false)
        }
    }

    /// Never rate-limited: leaving a screen, or a programmatic scroll to the
    /// top, must put the bar back whatever the auto-hiding was doing.
    func showBars() {
        setHidden(false, force: true)
    }

    /// Content shorter than the viewport would still trigger hides
    /// from the rubber-band bounce — keep the bar for it.
    private func canScroll(_ scrollView: UIScrollView) -> Bool {
        let insets = scrollView.adjustedContentInset
        let visible = scrollView.bounds.height - insets.top - insets.bottom
        return scrollView.contentSize.height > visible
    }

    /// Offset of the bottom rest position — anything past it is the
    /// bottom rubber band.
    private func bottomOffsetY(_ scrollView: UIScrollView) -> CGFloat {
        scrollView.contentSize.height
            + scrollView.adjustedContentInset.bottom
            - scrollView.bounds.height
    }

    private func setHidden(_ hidden: Bool, force: Bool = false) {
        guard isHidden != hidden else {
            return
        }
        // The state guard above stops a repeat of the same state, but not an
        // alternation between two — which is exactly what the livelock is.
        let now = CACurrentMediaTime()
        guard force || now - lastToggleAt >= Self.minimumToggleInterval else {
            return
        }
        lastToggleAt = now
        isHidden = hidden
        isToggling = true
        owner?.visibleNavigationController?
            .setNavigationBarHidden(hidden, animated: true)
        // Released a beat after the animation, on the main queue, so every
        // layout pass the toggle provokes has been and gone first.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.minimumToggleInterval
        ) { [weak self] in
            self?.isToggling = false
        }
        guard let onChange = onChange else {
            return
        }
        UIView.animate(withDuration: 0.22) {
            onChange(hidden)
        }
    }
}

// MARK: - Finding the bar that is on screen

extension UIViewController {
    /// The outermost navigation controller above this one. Library's segment
    /// children sit in an embedded navigation controller whose own bar is
    /// permanently hidden, so the bar the user sees belongs further up —
    /// hiding the nearest one there does nothing.
    var visibleNavigationController: UINavigationController? {
        sequence(first: self) { $0.parent }
            .compactMap { $0 as? UINavigationController }
            .last
    }
}
