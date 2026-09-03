import UIKit

/// Owns the focus state for one list, and the ring that draws it.
///
/// There is no focus engine to build on: `UIFocusSystem` arrived in iOS 15 and
/// `UIFocusGuide`, though it dates to iOS 9, has never done anything outside
/// tvOS. So movement, revealing and revalidation are all hand-rolled here.
final class ListFocusController: NSObject {
    enum Axis {
        case list, grid
    }

    /// Gap left between the focused cell and the edge of the visible area, so
    /// a focused card never sits flush under the navigation bar.
    private static let revealMargin: CGFloat = 12

    let axis: Axis
    private(set) var focused: IndexPath?

    private let ring = ListFocusRingView()
    private weak var geometry: FocusGeometry?
    private weak var host: AnyObject?

    /// The screen this controller belongs to, when it is still alive.
    var focusHost: ListFocusHost? { host as? ListFocusHost }

    /// Something on screen to hang a toast off — the list itself.
    var ringHostView: UIView? { geometry?.focusScrollView }
    private var contentSizeObservation: NSKeyValueObservation?
    /// Re-entrancy guard for the `contentSize` observer.
    ///
    /// The ring is a subview of the scroll view, so moving it triggers a
    /// layout pass, and a layout pass can recompute `contentSize` — which
    /// fires this observer again. On device that recursed until the stack hit
    /// its guard page: EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE with the same
    /// four frames repeating through Foundation and UIKit. Scrolling made it
    /// certain, because paging appends and changes `contentSize` for real.
    private var isAdjustingRing = false

    init(axis: Axis, geometry: FocusGeometry, host: ListFocusHost? = nil) {
        self.axis = axis
        self.geometry = geometry
        self.host = host
        super.init()
        ring.controller = self
        geometry.focusScrollView.addSubview(ring)
        observeContentSize(geometry.focusScrollView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.revalidate),
            name: UIApplication.didChangeStatusBarOrientationNotification,
            object: nil
        )
    }

    func move(_ direction: FocusDirection) {
        guard let geometry = geometry else {
            return
        }
        guard let current = focused else {
            KeyboardDiagnostics.logTimed("focus establish \(direction)")
            setFocus(geometry.firstFocusableIndexPath(), animated: true)
            return
        }
        let started = CACurrentMediaTime()
        let next = target(from: current, direction: direction, geometry: geometry)
        let elapsed = (CACurrentMediaTime() - started) * 1_000_000
        // "no move" rather than "-> none": nothing is cleared when the search
        // comes up empty at an edge, focus simply stays put, and a log that
        // reads like a clear will cost someone an hour in a later session.
        let outcome = next.map { self.describe($0) } ?? "no move"
        KeyboardDiagnostics.logTimed(
            "focus \(direction) \(describe(current))->\(outcome) " +
            String(format: "%.0fus", elapsed)
        )
        guard let next = next else {
            if direction == .up, escapeTop() {
                setFocus(nil, animated: false)
            }
            return
        }
        setFocus(next, animated: true)
    }

    /// Up at the topmost item: offer it to the screen before swallowing it.
    private func escapeTop() -> Bool {
        guard let host = focusHost, host.listFocusDidReachTop() else {
            return false
        }
        KeyboardDiagnostics.log("focus left the top, screen took the chain")
        return true
    }

    func activate() {
        guard let geometry = geometry,
              let focused = focused,
              geometry.isValid(focused)
        else {
            return
        }
        KeyboardDiagnostics.log("focus activate \(describe(focused))")
        geometry.focusSelect(focused)
    }

    func moveSection(forward: Bool) {
        guard let geometry = geometry else {
            return
        }
        let section = focused?.section ?? -1
        let next = forward
            ? ListFocusSearch.firstItem(ofSectionAfter: section, geometry: geometry)
            : ListFocusSearch.lastItem(ofSectionBefore: section, geometry: geometry)
        KeyboardDiagnostics.logTimed(
            "focus section \(forward ? "next" : "prev") -> \(describe(next))"
        )
        guard let next = next else {
            return
        }
        setFocus(next, animated: false)
    }

    func jump(toTop: Bool) {
        guard let geometry = geometry else {
            return
        }
        let next: IndexPath?
        if toTop {
            next = geometry.firstFocusableIndexPath()
        } else {
            next = ListFocusSearch.lastItem(
                ofSectionBefore: geometry.focusSectionCount,
                geometry: geometry
            )
        }
        KeyboardDiagnostics.logTimed("focus jump top=\(toTop) -> \(describe(next))")
        setFocus(next, animated: false)
    }

    /// One viewport in the requested direction, then the nearest real cell to
    /// where that landed.
    func page(forward: Bool) {
        guard let geometry = geometry,
              let current = focused,
              let frame = geometry.focusFrame(for: current)
        else {
            move(forward ? .down : .up)
            return
        }
        let height = geometry.focusScrollView.bounds.height
        let targetY = frame.midY + (forward ? height : -height)
        let band = CGRect(
            x: 0,
            y: targetY - height / 2,
            width: max(geometry.focusScrollView.bounds.width, frame.maxX),
            height: height
        )
        let nearest = geometry.focusCandidates(in: band)
            .compactMap { path -> (IndexPath, CGFloat)? in
                guard let candidate = geometry.focusFrame(for: path) else {
                    return nil
                }
                return (path, abs(candidate.midY - targetY))
            }
            .min { $0.1 < $1.1 }?
            .0
        KeyboardDiagnostics.logTimed("focus page fwd=\(forward) -> \(describe(nearest))")
        setFocus(nearest ?? current, animated: false)
    }

    func clearFocus() {
        KeyboardDiagnostics.log("focus cleared")
        setFocus(nil, animated: false)
    }

    /// Fires on every layout change that moves cells: `reloadData` from a
    /// refresh or a category switch, the batch update that appends a page, the
    /// invalidation when the item size is recomputed, and rotation. One
    /// observation covers all of them, which is what keeps the focus layer out
    /// of every screen's reload path.
    @objc
    func revalidate() {
        guard !isAdjustingRing else {
            return
        }
        guard let geometry = geometry, let focused = focused else {
            return
        }
        isAdjustingRing = true
        defer { self.isAdjustingRing = false }
        guard geometry.isValid(focused),
              let frame = geometry.focusFrame(for: focused)
        else {
            KeyboardDiagnostics.log("focus dropped: \(describe(focused)) no longer exists")
            setFocus(nil, animated: false)
            return
        }
        ring.show(at: frame)
    }
}

// MARK: - Private

private extension ListFocusController {
    func target(
        from current: IndexPath,
        direction: FocusDirection,
        geometry: FocusGeometry
    ) -> IndexPath? {
        let vertical = direction == .up || direction == .down
        if axis == .list {
            guard vertical else {
                return nil
            }
            return ListFocusSearch.step(
                from: current,
                forward: direction == .down,
                geometry: geometry
            )
        }
        if let found = ListFocusSearch.next(
            from: current,
            direction: direction,
            geometry: geometry
        ) {
            return found
        }
        guard vertical else {
            return nil
        }
        return ListFocusSearch.step(
            from: current,
            forward: direction == .down,
            geometry: geometry
        )
    }

    func setFocus(_ indexPath: IndexPath?, animated: Bool) {
        let wasAdjusting = isAdjustingRing
        isAdjustingRing = true
        defer { self.isAdjustingRing = wasAdjusting }
        focused = indexPath
        guard let indexPath = indexPath,
              let geometry = geometry,
              let frame = geometry.focusFrame(for: indexPath)
        else {
            ring.hide()
            return
        }
        ring.show(at: frame)
        reveal(frame, animated: animated)
    }

    /// Hand-rolled rather than `scrollToItem(at:at:animated:)`: that ignores
    /// content insets before iOS 11, leaves no breathing room, and gives no say
    /// over whether the move animates. A jump across a long feed should not.
    func reveal(_ frame: CGRect, animated: Bool) {
        guard let scrollView = geometry?.focusScrollView else {
            return
        }
        let inset = scrollView.adjustedContentInset
        let offset = scrollView.contentOffset
        let visibleTop = offset.y + inset.top
        let visibleBottom = offset.y + scrollView.bounds.height - inset.bottom
        var targetY = offset.y
        if frame.minY - Self.revealMargin < visibleTop {
            targetY -= visibleTop - (frame.minY - Self.revealMargin)
        } else if frame.maxY + Self.revealMargin > visibleBottom {
            targetY += (frame.maxY + Self.revealMargin) - visibleBottom
        } else {
            return
        }
        let lowest = -inset.top
        let highest = max(
            lowest,
            scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
        )
        targetY = min(max(targetY, lowest), highest)
        scrollView.setContentOffset(
            CGPoint(x: offset.x, y: targetY),
            animated: animated
        )
    }

    /// `contentSize`, deliberately, and not `bounds` — bounds changes on every
    /// scrolled frame, which would put this on the hot path for nothing.
    func observeContentSize(_ scrollView: UIScrollView) {
        contentSizeObservation = scrollView.observe(
            \.contentSize,
            options: [.new]
        ) { [weak self] _, _ in
            self?.revalidate()
        }
    }

}
