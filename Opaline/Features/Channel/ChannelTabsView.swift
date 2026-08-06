import UIKit

/// The channel's Videos / Live / Playlists switch. Underlined text, so
/// it never reads as another row of the filter chips below it.
final class ChannelTabsView: UIView {
    enum Tab: Int {
        case videos = 0
        case live = 1
        case playlists = 2
    }

    static let preferredHeight: CGFloat = 40

    var onTabSelected: ((Tab) -> Void)?

    private let stack = UIStackView()
    private let underline = UIView()
    private let hairline = UIView()
    private var buttons: [UIButton] = []
    private var underlineRefs: [NSLayoutConstraint] = []
    private var selectedIndex = Tab.videos.rawValue

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupView()
        moveUnderline(animated: false)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        underline.backgroundColor = theme.accent
        hairline.backgroundColor = theme.separator
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.setTitleColor(
                selected ? theme.primaryText : theme.secondaryText,
                for: .normal
            )
            button.titleLabel?.font = .systemFont(
                ofSize: 15, weight: selected ? .semibold : .regular
            )
        }
    }

    private func setupView() {
        buildButtons()
        stack.axis = .horizontal
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.forEach { stack.addArrangedSubview($0) }
        // Trailing spacer keeps the tabs left-aligned on wide screens.
        stack.addArrangedSubview(UIView())
        [underline, hairline].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(stack)
        addSubview(hairline)
        addSubview(underline)
        activateConstraints()
    }

    private func buildButtons() {
        let titles = [
            "channel.tab.videos".localized,
            "channel.tab.live".localized,
            "channel.tab.playlists".localized
        ]
        buttons = titles.enumerated().map { index, title in
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.tag = index
            button.addTarget(
                self, action: #selector(tabTapped(_:)), for: .touchUpInside
            )
            return button
        }
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 16
            ),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -16
            ),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    /// Pins the underline to the selected button's title width.
    private func moveUnderline(animated: Bool) {
        guard let label = buttons[selectedIndex].titleLabel else {
            return
        }
        NSLayoutConstraint.deactivate(underlineRefs)
        underlineRefs = [
            underline.centerXAnchor.constraint(equalTo: label.centerXAnchor),
            underline.widthAnchor.constraint(
                equalTo: label.widthAnchor, constant: 16
            )
        ]
        NSLayoutConstraint.activate(underlineRefs)
        guard animated else {
            return
        }
        UIView.animate(withDuration: 0.2) { self.layoutIfNeeded() }
    }

    @objc
    private func tabTapped(_ sender: UIButton) {
        guard sender.tag != selectedIndex else {
            return
        }
        selectedIndex = sender.tag
        applyTheme()
        moveUnderline(animated: true)
        onTabSelected?(Tab(rawValue: selectedIndex) ?? .videos)
    }
}
