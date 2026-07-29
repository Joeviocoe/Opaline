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

        let color = item.isDestructive ? UIColor.systemRed : rowColor
        addRowLabel(item.title, color: color, hasIcons: hasIcons, to: button)
        if let iconName = item.iconName {
            addRowIcon(iconName, color: color, to: button)
        }
        return button
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
