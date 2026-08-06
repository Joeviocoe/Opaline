import UIKit

final class PlaylistSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "PlaylistSectionHeaderView"

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(
            ofSize: 16,
            weight: .semibold
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 8
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -8
            ),
            titleLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 4
            ),
            titleLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -4
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func configure(title: String, color: UIColor?) {
        titleLabel.text = title
        titleLabel.textColor = color
    }
}
