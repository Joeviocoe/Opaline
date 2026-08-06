import UIKit

/// One icon-over-count action in the Shorts rail. White on video, so it
/// ignores the theme — the backdrop is always the playing short.
final class ShortsActionButton: UIView {
    var onTap: (() -> Void)?

    var count: String? {
        didSet {
            label.text = count
            label.isHidden = count == nil
        }
    }

    var isHighlighted = false {
        didSet { applyTint() }
    }

    private let button = UIButton(type: .custom)
    private let label = UILabel()

    init(icon: String) {
        super.init(frame: .zero)
        button.setImage(
            UIImage(named: icon)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        button.addTarget(
            self, action: #selector(tapped), for: .touchUpInside
        )
        setupLayout()
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.isHidden = true
        let stack = UIStackView(arrangedSubviews: [button, label])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func applyTint() {
        button.tintColor = isHighlighted
            ? ThemeManager.shared.accent : .white
    }

    @objc
    private func tapped() {
        onTap?()
    }
}
