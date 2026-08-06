import UIKit

/// Horizontal scrollable chip bar — used both for the channel's tabs
/// and for a tab's filter chips.
final class ChannelFilterBarView: UIView {
    static let preferredHeight: CGFloat = 44

    var onSelect: ((Int) -> Void)?
    var titleFont: UIFont = .systemFont(ofSize: 13, weight: .medium)

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var titles: [String] = []
    private var buttons: [UIButton] = []
    private var selectedIndex: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setTitles(_ titles: [String], selected: Int) {
        self.titles = titles
        self.selectedIndex = selected
        rebuildButtons()
        applyTheme()
    }

    func clearTitles() {
        titles = []
        buttons = []
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    func applyTheme() {
        backgroundColor = ThemeManager.shared.background
        for (i, btn) in buttons.enumerated() {
            styleButton(btn, selected: i == selectedIndex)
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -16)
        ])
        heightAnchor.constraint(
            equalToConstant: Self.preferredHeight
        ).isActive = true
    }

    private func rebuildButtons() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = titles.enumerated().map { idx, title in
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = titleFont
            btn.layer.cornerRadius = 14
            btn.layer.borderWidth = 1
            btn.contentEdgeInsets = UIEdgeInsets(
                top: 6, left: 14, bottom: 6, right: 14
            )
            btn.tag = idx
            btn.addTarget(
                self, action: #selector(chipTapped(_:)), for: .touchUpInside
            )
            return btn
        }
        buttons.forEach { stack.addArrangedSubview($0) }
    }

    @objc
    private func chipTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard idx != selectedIndex, idx < titles.count else {
            return
        }
        selectedIndex = idx
        applyTheme()
        onSelect?(idx)
    }

    private func styleButton(_ btn: UIButton, selected: Bool) {
        let accent = ThemeManager.shared.accent
        let textColor = ThemeManager.shared.primaryText
        if selected {
            btn.backgroundColor = accent
            btn.setTitleColor(ThemeManager.shared.background, for: .normal)
            btn.layer.borderColor = accent.cgColor
        } else {
            btn.backgroundColor = .clear
            btn.setTitleColor(textColor, for: .normal)
            btn.layer.borderColor = textColor.withAlphaComponent(0.3).cgColor
        }
    }
}
