import UIKit

// MARK: - Row building

/// Builds a single menu row (optional leading icon + title). Split out of
/// `PlayerMenuOverlay.swift` to keep that file under the length limit.
extension PlayerMenuOverlay {
    func makeRow(item: PlayerMenuItem, index: Int, hasIcons: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index
        button.heightAnchor.constraint(
            equalToConstant: Metrics.rowHeight
        ).isActive = true
        button.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
        // The title and icon are plain subviews, so a system button's own
        // highlight never shows — the row needs its own pressed state.
        button.addTarget(self, action: #selector(rowPressed(_:)), for: .touchDown)
        button.addTarget(
            self,
            action: #selector(rowReleased(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )

        let color = item.isDestructive ? UIColor.systemRed : rowColor
        addRowLabel(item.title, color: color, hasIcons: hasIcons, to: button)
        if let iconName = item.iconName {
            addRowIcon(iconName, color: color, to: button)
        }
        return button
    }

    @objc
    func rowPressed(_ button: UIButton) {
        Feedback.tap()
        button.backgroundColor = rowColor.withAlphaComponent(0.12)
    }

    @objc
    func rowReleased(_ button: UIButton) {
        UIView.animate(withDuration: 0.2) {
            button.backgroundColor = .clear
        }
    }

    private func addRowLabel(
        _ text: String,
        color: UIColor,
        hasIcons: Bool,
        to button: UIButton
    ) {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = UIFont.systemFont(ofSize: Metrics.rowFontSize)
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        let leading = hasIcons ? Metrics.titleLeading : Metrics.iconLeading
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: leading),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: button.trailingAnchor, constant: -Metrics.rowTrailing
            )
        ])
    }

    private func addRowIcon(_ name: String, color: UIColor, to button: UIButton) {
        guard let image = UIImage(named: name) else {
            return
        }
        let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            imageView.leadingAnchor.constraint(
                equalTo: button.leadingAnchor, constant: Metrics.iconLeading
            ),
            imageView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: Metrics.iconSize)
        ])
    }
}
