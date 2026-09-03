import UIKit

/// The focus highlight, which is also the first responder that drives it.
///
/// It is a subview of the scroll view, positioned in *content* coordinates.
/// Three things follow from that and each one is the reason for the choice:
///
///  * it scrolls with the content for free — no `scrollViewDidScroll` hook and
///    no geometry work per frame, which on an A5X is the difference between a
///    smooth flick and a visibly janky one;
///  * it survives cell reuse, because it is not attached to a cell. No cell
///    class changes; none of them render `isSelected` today anyway
///    (`selectionStyle = .none` everywhere, no `setSelected` overrides);
///  * the responder chain lands right: ring -> list -> vc.view -> VC -> nav ->
///    tab -> root. The screen's own controller sits *above* the ring, which is
///    what lets the player keep the arrow keys while a list is on screen.
///
/// It is never hidden and never fully transparent even with no focus — a
/// hidden view is not a dependable first responder — so "no focus" is drawn as
/// a zero-width border on a 1x1 frame instead.
final class ListFocusRingView: UIView {
    private static let borderWidth: CGFloat = 3
    private static let cornerRadius: CGFloat = 6
    /// How far outside the cell the ring sits. Small enough to stay inside the
    /// inter-cell gutter on the feed grid, so it mostly draws against the page
    /// background rather than over artwork.
    static let outset: CGFloat = 2

    weak var controller: ListFocusController?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard !KeyboardInputMonitor.shared.isEditingText else {
            return nil
        }
        guard let controller = controller else {
            return nil
        }
        // Deliberately not logged. UIKit asks for this on every responder-chain
        // walk, not once per keypress, and AppLog does a print plus a queue
        // hop per line -- which is real frame budget on an A5X for a line that
        // says nothing a command fire does not already say.
        return KeyCommandCatalog.focus(
            axis: controller.axis,
            hasFocus: controller.focused != nil
        )
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        layer.borderWidth = 0
        layer.cornerRadius = Self.cornerRadius
        layer.zPosition = 1_000
        backgroundColor = .clear
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Transparent to touch despite being interactive — interaction has to stay
    /// enabled for first-responder status, but the ring must never swallow a
    /// tap meant for the cell underneath it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            KeyboardFocusCoordinator.shared.ringDidLeaveWindow(self)
            resignFirstResponder()
            KeyboardDiagnostics.log("ring left window")
            return
        }
        KeyboardFocusCoordinator.shared.ringDidEnterWindow(self)
        // Never take the chain off a field someone is typing in. Search calls
        // `searchBar.becomeFirstResponder()` in `viewDidAppear`, and `didShow`
        // — which installs this ring — fires immediately after, so without this
        // the ring stole focus microseconds after the field got it and the
        // screen opened with no cursor.
        guard !KeyboardInputMonitor.shared.isEditingText else {
            KeyboardDiagnostics.log("ring stands down: a text field is editing")
            return
        }
        let accepted = becomeFirstResponder()
        KeyboardDiagnostics.logResponder("ring becomeFirstResponder", self, accepted: accepted)
    }

    func show(at frame: CGRect) {
        let target = frame.insetBy(dx: -Self.outset, dy: -Self.outset)
        // Assigning an unchanged frame still dirties layout, and a layout pass
        // on the enclosing scroll view is exactly what re-enters the observer
        // that called this. Cheapest fix is to not write when nothing moved.
        if self.frame != target {
            self.frame = target
        }
        if layer.borderWidth != Self.borderWidth {
            layer.borderWidth = Self.borderWidth
        }
    }

    func hide() {
        layer.borderWidth = 0
        frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// White on dark, black on light.
    ///
    /// Deliberately *not* `ThemeManager.accent`: that is hard-coded pure red in
    /// both themes, and red already means the selected-channel ring in the
    /// subscriptions avatar bar — which can be on screen at the same time as
    /// this one — as well as the live badge, both progress bars, the subscribe
    /// button and link text. Monochrome is the only choice left that collides
    /// with nothing.
    @objc
    private func applyTheme() {
        let stroke: UIColor = ThemeManager.shared.isDark ? .white : .black
        layer.borderColor = stroke.cgColor
    }
}

// MARK: - Key Actions

extension ListFocusRingView {
    @objc
    func focusMoveUp() { controller?.move(.up) }

    @objc
    func focusMoveDown() { controller?.move(.down) }

    @objc
    func focusMoveLeft() { controller?.move(.left) }

    @objc
    func focusMoveRight() { controller?.move(.right) }

    @objc
    func focusActivate() { controller?.activate() }

    @objc
    func focusNextSection() { controller?.moveSection(forward: true) }

    @objc
    func focusPreviousSection() { controller?.moveSection(forward: false) }

    @objc
    func focusJumpToTop() { controller?.jump(toTop: true) }

    @objc
    func focusJumpToBottom() { controller?.jump(toTop: false) }

    @objc
    func focusPageUp() { controller?.page(forward: false) }

    @objc
    func focusPageDown() { controller?.page(forward: true) }

    @objc
    func focusClear() { controller?.clearFocus() }

    @objc
    func focusQueue() { controller?.queueFocused() }
}
