import UIKit

/// Table header banner shown in the inbox while system notifications are
/// off — explains why and offers a one-tap fix (request or open Settings).
final class NotificationPermissionBannerView: UIView {
    var onEnable: (() -> Void)?

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 13)
        label.text = "notifications.permissionBanner.message".localized
        return label
    }()

    private let enableButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("notifications.permissionBanner.enable".localized, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        enableButton.translatesAutoresizingMaskIntoConstraints = false
        enableButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addSubview(messageLabel)
        addSubview(enableButton)
        // The table assigns the header's frame height, which fights the
        // bottom constraint during intermediate layout passes — let the
        // bottom one yield instead of logging a conflict.
        let bottom = enableButton.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: -12
        )
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            enableButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            enableButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottom
        ])
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.surface
        messageLabel.textColor = theme.secondaryText
        enableButton.tintColor = theme.accent
    }

    /// Table header views need an explicit frame — asks Auto Layout for the
    /// height this content needs at the given width.
    func sized(for width: CGFloat) -> UIView {
        frame = CGRect(x: 0, y: 0, width: width, height: 1)
        let height = systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        return self
    }

    @objc
    private func tapped() {
        onEnable?()
    }
}
