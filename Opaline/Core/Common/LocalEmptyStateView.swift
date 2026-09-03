import UIKit

/// Empty state for a local library that simply has nothing in it yet.
///
/// Deliberately not `SignInEmptyStateView`: nothing here is broken and
/// nothing needs an account, so the screen should say what to do rather than
/// ask for a sign-in the user already declined.
final class LocalEmptyStateView: UIView {
    private let iconImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = .lightGray
        view.translatesAutoresizingMaskIntoConstraints = false
        if let asset = LegacyAssets.image("icon_person_fill") {
            view.image = asset
        } else if #available(iOS 13, *) {
            view.image = UIImage(systemName: "square.stack")
        }
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = message
        addSubview(iconImageView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(
                equalTo: iconImageView.bottomAnchor, constant: 16
            ),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func setMessage(_ message: String) {
        titleLabel.text = message
    }
}
