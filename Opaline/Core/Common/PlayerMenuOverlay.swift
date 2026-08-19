import UIKit

/// A single row in a `PlayerMenuOverlay`.
struct PlayerMenuItem {
    let title: String
    var isDestructive = false
    /// Asset catalog name of a template icon shown leading the title.
    var iconName: String?
    let handler: (() -> Void)?
}

/// The one menu UI for all player menus, inline and fullscreen alike.
/// A system alert could not serve the fullscreen case: there the player view
/// is attached directly to the window, above anything the watch controller
/// presents — and in iPhone landscape it is rotated by a transform, which a
/// presented alert would not follow. Hosting the menu in the player's own
/// hierarchy solves both; dismissal is a tap outside the panel.
final class PlayerMenuOverlay: UIView {
    /// `overVideo` keeps the player's dark chrome regardless of app theme;
    /// `themed` follows `ThemeManager` for menus hosted over regular UI.
    enum Style {
        case overVideo
        case themed
    }

    /// Larger touch targets on iPad — 44pt rows are hard to hit on the
    /// mini's dense screen; iPhone keeps the compact layout.
    enum Metrics {
        static let isPad = UIDevice.current.userInterfaceIdiom == .pad
        static let panelWidth: CGFloat = isPad ? 360 : 280
        static let rowHeight: CGFloat = isPad ? 56 : 44
        static let rowFontSize: CGFloat = isPad ? 17 : 15
        static let titleFontSize: CGFloat = isPad ? 15 : 13
        /// Eight rows before scrolling kicks in. The panel is separately
        /// capped to the host's height, so a short screen still fits.
        static let maxRowsHeight: CGFloat = isPad ? 448 : 352
        static let iconSize: CGFloat = 22
        static let iconLeading: CGFloat = 16
        static let iconTitleGap: CGFloat = 10
        static let rowTrailing: CGFloat = 16
        /// Column titles start at, whether or not their row has an icon.
        static let titleLeading: CGFloat = iconLeading + iconSize + iconTitleGap
        /// Keeps the anchored panel from ever touching the host's edges.
        static let edgeMargin: CGFloat = 8
    }

    private(set) var items: [PlayerMenuItem] = []
    private var style: Style = .overVideo
    let panel = UIView()

    private var panelColor: UIColor {
        style == .overVideo
            ? UIColor.black.withAlphaComponent(0.9)
            : ThemeManager.shared.surface
    }

    private var titleColor: UIColor {
        style == .overVideo
            ? UIColor.white.withAlphaComponent(0.6)
            : ThemeManager.shared.secondaryText
    }

    var rowColor: UIColor {
        style == .overVideo ? .white : ThemeManager.shared.primaryText
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleBackgroundTap(_:))
        )
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    /// - Parameter sourceRect: the tapped control's frame, in `host`'s
    ///   coordinate space. `nil` keeps the historical centered placement
    ///   the player menus depend on; otherwise the panel anchors next to
    ///   it, clamped fully inside `host`.
    static func show(
        in host: UIView,
        title: String?,
        items: [PlayerMenuItem],
        style: Style = .overVideo,
        from sourceRect: CGRect? = nil
    ) {
        let overlay = PlayerMenuOverlay(frame: host.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.items = items
        overlay.style = style
        overlay.backgroundColor = UIColor.black
            .withAlphaComponent(style == .overVideo ? 0.4 : 0.25)
        overlay.buildContent(title: title, sourceRect: sourceRect)
        host.addSubview(overlay)
        if sourceRect != nil {
            overlay.observeRotation()
        }
        overlay.alpha = 0
        UIView.animate(withDuration: 0.15) {
            overlay.alpha = 1
        }
    }

    // MARK: - Layout

    /// An anchored panel is pinned by a constant computed for the bounds it
    /// was built in, so a rotation would strand it — often half offscreen.
    /// Dismissing is what system menus do too. The centered player menus
    /// re-center themselves and never register this.
    private func observeRotation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRotation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    @objc
    private func handleRotation() {
        dismiss()
    }

    private func buildContent(title: String?, sourceRect: CGRect?) {
        panel.backgroundColor = panelColor
        panel.layer.cornerRadius = 10
        panel.layer.masksToBounds = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        let titleLabel = title.map { makeTitleLabel($0) }
        titleLabel.map { panel.addSubview($0) }
        let scroll = makeRowsScrollView()
        panel.addSubview(scroll)
        activatePanelConstraints(titleLabel: titleLabel, scroll: scroll, sourceRect: sourceRect)
    }

    private func makeTitleLabel(_ text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = titleColor
        titleLabel.font = UIFont.systemFont(
            ofSize: Metrics.titleFontSize, weight: .semibold
        )
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }

    private func makeRowsScrollView() -> UIScrollView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Only reserve an icon column when some row in this menu actually
        // has one — the player's menus never do, and must keep their
        // original 16pt title inset.
        let hasIcons = items.contains { $0.iconName != nil }
        for (index, item) in items.enumerated() {
            stack.addArrangedSubview(makeRow(item: item, index: index, hasIcons: hasIcons))
        }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let content = scroll.contentLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        // Size the scroll view to its rows; breaks against the height caps
        // in `activatePanelConstraints` when the list is long.
        let fit = scroll.heightAnchor.constraint(equalTo: stack.heightAnchor)
        fit.priority = .defaultHigh
        fit.isActive = true
        return scroll
    }

    private func activatePanelConstraints(
        titleLabel: UILabel?,
        scroll: UIScrollView,
        sourceRect: CGRect?
    ) {
        var constraints: [NSLayoutConstraint] = [
            panel.widthAnchor.constraint(equalToConstant: Metrics.panelWidth),
            panel.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -32)
        ]
        constraints += positionConstraints(sourceRect: sourceRect, hasTitle: titleLabel != nil)
        constraints += titleAndScrollConstraints(titleLabel: titleLabel, scroll: scroll)
        NSLayoutConstraint.activate(constraints)
    }

    private func titleAndScrollConstraints(
        titleLabel: UILabel?,
        scroll: UIScrollView
    ) -> [NSLayoutConstraint] {
        var constraints: [NSLayoutConstraint] = []
        if let titleLabel {
            constraints += [
                titleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
                titleLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
                scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
            ]
        } else {
            constraints.append(scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8))
        }
        constraints += [
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(
                lessThanOrEqualToConstant: Metrics.maxRowsHeight
            )
        ]
        return constraints
    }

    // MARK: - Actions

    @objc
    private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        guard !panel.frame.contains(location) else {
            return
        }
        dismiss()
    }

    @objc
    func rowTapped(_ button: UIButton) {
        guard button.tag < items.count else {
            return
        }
        let handler = items[button.tag].handler
        dismiss()
        handler?()
    }

    private func dismiss() {
        UIView.animate(
            withDuration: 0.15,
            animations: { self.alpha = 0 },
            completion: { _ in self.removeFromSuperview() }
        )
    }
}
