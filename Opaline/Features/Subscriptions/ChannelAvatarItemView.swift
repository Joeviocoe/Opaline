import UIKit

final class ChannelAvatarCell: UICollectionViewCell {
    private let itemView = ChannelAvatarItemView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(itemView)
        NSLayoutConstraint.activate([
            itemView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            itemView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with channel: SubscribedChannel) {
        itemView.configure(with: channel)
    }

    func setSelected(_ selected: Bool) {
        itemView.setSelected(selected)
    }

    func setShowsNewContent(_ shows: Bool) {
        itemView.setShowsNewContent(shows)
    }

    func applyTheme() {
        itemView.applyTheme()
    }
}

/// Single avatar with the channel name underneath and an accent ring
/// when selected. Instantiated once per `ChannelAvatarCell` and
/// rebound on reuse via `configure(with:)` — never per-channel.
final class ChannelAvatarItemView: UIView {
    static let avatarSize: CGFloat = 48
    static let ringSize: CGFloat = 56
    static let itemWidth: CGFloat = 64

    private let ringView = UIView()
    private let avatarView = ChannelAvatarView()
    private let nameLabel = UILabel()
    private let dotView = NewContentDotView()
    private var isRingSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with channel: SubscribedChannel) {
        avatarView.configure(with: channel)
        nameLabel.text = channel.title
    }

    func setSelected(_ selected: Bool) {
        isRingSelected = selected
        ringView.layer.borderWidth = selected ? 2 : 0
        ringView.layer.borderColor = ThemeManager.shared.accent.cgColor
        nameLabel.font = .systemFont(
            ofSize: 11,
            weight: selected ? .semibold : .regular
        )
        applyNameColor()
    }

    func setShowsNewContent(_ shows: Bool) {
        dotView.isHidden = !shows
    }

    func applyTheme() {
        avatarView.applyTheme()
        dotView.applyTheme()
        applyNameColor()
    }

    private func applyNameColor() {
        let theme = ThemeManager.shared
        nameLabel.textColor = isRingSelected
            ? theme.primaryText : theme.secondaryText
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setupRingAndAvatar()
        setupNameLabel()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(
                equalToConstant: ChannelAvatarItemView.itemWidth
            ),
            ringView.topAnchor.constraint(equalTo: topAnchor),
            ringView.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatarView.centerXAnchor.constraint(
                equalTo: ringView.centerXAnchor
            ),
            avatarView.centerYAnchor.constraint(
                equalTo: ringView.centerYAnchor
            ),
            nameLabel.topAnchor.constraint(
                equalTo: ringView.bottomAnchor,
                constant: 3
            ),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupRingAndAvatar() {
        let ring = ChannelAvatarItemView.ringSize
        let avatar = ChannelAvatarItemView.avatarSize
        ringView.layer.cornerRadius = ring / 2
        ringView.isUserInteractionEnabled = false
        ringView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringView)
        addSubview(avatarView)
        addSubview(dotView)
        dotView.constrainToTopRight(of: avatarView)
        NSLayoutConstraint.activate([
            ringView.widthAnchor.constraint(equalToConstant: ring),
            ringView.heightAnchor.constraint(equalToConstant: ring),
            avatarView.widthAnchor.constraint(equalToConstant: avatar),
            avatarView.heightAnchor.constraint(equalToConstant: avatar)
        ])
    }

    private func setupNameLabel() {
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.numberOfLines = 1
        nameLabel.isUserInteractionEnabled = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
    }
}
