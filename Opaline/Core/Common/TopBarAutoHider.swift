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

    /// The bar that is actually on screen — Library's segment children
    /// live in an embedded navigation controller whose own bar is
    /// permanently hidden, so climb to the outermost one.
    private var navigationController: UINavigationController? {
        var found: UINavigationController?
        var node: UIViewController? = owner
        while let current = node {
            if let nav = current as? UINavigationController {
                found = nav
            }
            node = current.parent
        }
        return found
    }

    init(owner: UIViewController) {
        self.owner = owner
    }

    func handleScroll(_ scrollView: UIScrollView) {
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

    func showBars() {
        setHidden(false)
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

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else {
            return
        }
        isHidden = hidden
        navigationController?.setNavigationBarHidden(hidden, animated: true)
        guard let onChange else {
            return
        }
        UIView.animate(withDuration: 0.22) {
            onChange(hidden)
        }
    }
}
