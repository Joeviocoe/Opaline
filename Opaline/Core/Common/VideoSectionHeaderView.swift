import UIKit

/// Section header for video grids — shows the shelf title
/// ("Recommended", "Gaming", …) above its run of videos.
final class VideoSectionHeaderView: UICollectionReusableView {
    static let reuseId = "VideoSectionHeader"
    static let height: CGFloat = 36

    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String?) {
        label.text = title
        label.textColor = ThemeManager.shared.primaryText
    }
}
