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

    func setRefreshing(_ refreshing: Bool) {
        itemView.setRefreshing(refreshing)
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
    /// Three-quarter arc on the ring, spun while this channel's uploads are
    /// being fetched — the refresh's progress, shown where it is happening
    /// instead of in a spinner row that shoves the list down.
    private let progressLayer = CAShapeLayer()
    private static let spinKey = "spin"
    private var isRingSelected = false
    private var isRefreshing = false

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
        applyRing()
        nameLabel.font = .systemFont(
            ofSize: 11,
            weight: selected ? .semibold : .regular
        )
        applyNameColor()
    }

    /// Re-adds the animation every time rather than only on a change: cells
    /// are reused, and Core Animation drops animations when the app goes to
    /// the background, so "already spinning" is not something to trust.
    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        applyRing()
        progressLayer.removeAnimation(forKey: ChannelAvatarItemView.spinKey)
        progressLayer.isHidden = !refreshing
        guard refreshing else {
            return
        }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 1
        spin.repeatCount = .infinity
        progressLayer.add(spin, forKey: ChannelAvatarItemView.spinKey)
    }

    /// The selection ring and the progress arc sit on the same circle in the
    /// same colour, so while spinning the ring steps back to let the arc
    /// read as movement rather than vanish into it.
    private func applyRing() {
        let accent = ThemeManager.shared.accent
        ringView.layer.borderWidth = isRingSelected ? 2 : 0
        ringView.layer.borderColor = (
            isRefreshing ? accent.withAlphaComponent(0.3) : accent
        ).cgColor
        progressLayer.strokeColor = accent.cgColor
    }

    func setShowsNewContent(_ shows: Bool) {
        dotView.isHidden = !shows
    }

    func applyTheme() {
        avatarView.applyTheme()
        dotView.applyTheme()
        applyRing()
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
        setupProgressLayer(ring: ring)
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

    /// Same circle and width as the selection border, so the two overlay
    /// exactly. The ring's size is a constant, so the layer's frame can be.
    private func setupProgressLayer(ring: CGFloat) {
        let inset: CGFloat = 1
        progressLayer.frame = CGRect(x: 0, y: 0, width: ring, height: ring)
        progressLayer.path = UIBezierPath(
            ovalIn: CGRect(
                x: inset, y: inset,
                width: ring - inset * 2, height: ring - inset * 2
            )
        ).cgPath
        progressLayer.fillColor = nil
        progressLayer.lineWidth = 2
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0.75
        progressLayer.isHidden = true
        ringView.layer.addSublayer(progressLayer)
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
