import UIKit

/// A vertical Shorts poster with its title and view count. Shared UI: the
/// subscriptions shelf and the channel's Shorts grid both show this 9:16
/// card, only the layout around it differs.
final class ShortThumbnailCell: UICollectionViewCell {
    static let reuseIdentifier = "ShortThumbnailCell"
    /// Height the title and view count add below the poster.
    static let captionHeight: CGFloat = 46
    /// Shorts are 9:16; the poster keeps that ratio at any width.
    static let aspectRatio: CGFloat = 16.0 / 9.0

    private let poster = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let viewsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        poster.cancel()
        poster.image = nil
    }

    func configure(with video: Video) {
        titleLabel.text = video.title
        viewsLabel.text = video.viewCount
        // The short's own first frame — feed thumbnails are landscape and
        // would sit letterboxed inside a 9:16 card.
        if let url = URL(
            string: "https://i.ytimg.com/vi/\(video.id)/frame0.jpg"
        ) {
            poster.setImage(url: url)
        }
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        titleLabel.textColor = theme.primaryText
        viewsLabel.textColor = theme.secondaryText
        poster.backgroundColor = theme.thumbnailPlaceholder
    }

    private func setupViews() {
        poster.contentMode = .scaleAspectFill
        poster.layer.cornerRadius = 8
        poster.clipsToBounds = true
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.numberOfLines = 2
        viewsLabel.font = .systemFont(ofSize: 12)

        let stack = UIStackView(arrangedSubviews: [
            poster, titleLabel, viewsLabel
        ])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(6, after: poster)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor
            ),
            poster.heightAnchor.constraint(
                equalTo: poster.widthAnchor, multiplier: Self.aspectRatio
            )
        ])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
