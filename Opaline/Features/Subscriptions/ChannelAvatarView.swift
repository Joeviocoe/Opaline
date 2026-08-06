import UIKit

/// Circular channel avatar with a letter placeholder for missing images.
final class ChannelAvatarView: UIView {
    private let imageView = ThumbnailImageView(frame: .zero)
    private let initialLabel = UILabel()
    private var currentChannelId: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func configure(with channel: SubscribedChannel) {
        currentChannelId = channel.id
        let initial = channel.title.first.map(String.init)?.uppercased() ?? ""
        initialLabel.text = initial
        imageView.image = nil
        if let avatarURL = channel.avatarURL,
           let url = URL(string: avatarURL) {
            imageView.setImage(url: url)
        } else {
            imageView.cancel()
            resolveAvatar(channelId: channel.id)
        }
    }

    func reset() {
        currentChannelId = nil
        imageView.cancel()
        initialLabel.text = nil
    }

    /// Feed-derived channels may lack an avatar URL; resolve it via
    /// the disk-cached channel info store (same path the video
    /// cells use).
    private func resolveAvatar(channelId: String) {
        ChannelInfoStore.shared.fetch(
            channelId: channelId
        ) { [weak self] result in
            guard let self,
                  self.currentChannelId == channelId,
                  case .success(let info) = result,
                  let avatarURL = info.avatarURL,
                  let url = URL(string: avatarURL)
            else {
                return
            }
            self.imageView.setImage(url: url)
        }
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.thumbnailPlaceholder
        initialLabel.textColor = theme.secondaryText
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        isUserInteractionEnabled = false

        initialLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        initialLabel.textAlignment = .center
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialLabel)

        imageView.maxPixelSize = 96
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            initialLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        applyTheme()
    }
}
