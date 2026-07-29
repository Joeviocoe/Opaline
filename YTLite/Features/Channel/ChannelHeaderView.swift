import UIKit

final class ChannelHeaderView: UIView {
    var bannerImageView = ThumbnailImageView(frame: .zero)
    var bannerOverlay = UIView()
    var avatarView = ThumbnailImageView(frame: .zero)
    var nameLabel = UILabel()
    var verifiedBadgeView = UIImageView()
    var subscribersLabel = UILabel()
    let subscribeButton = UIButton(type: .system)
    var separatorView = UIView()
    var nameSkeleton = SkeletonBlockView(cornerRadius: 6)
    var subsSkeleton = SkeletonBlockView(cornerRadius: 4)
    var btnSkeleton = SkeletonBlockView(cornerRadius: 16)
    var heightRef: NSLayoutConstraint?
    /// Zero unless the channel is verified, so the name gets the space.
    var badgeWidthRef: NSLayoutConstraint?
    let expandedHeight: CGFloat = 140
    let collapsedHeight: CGFloat = 0
    let bannerHeight: CGFloat = 88
    let avatarSize: CGFloat = 64
    /// How far the avatar rides up over the banner's bottom edge.
    let avatarOverlap: CGFloat = 20

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        configureBanner()
        configureLabels()
        configureButtonAndSeparator()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    func install(
        in parent: UIView,
        collectionView cv: UICollectionView,
        errorLabel: UILabel
    ) {
        parent.addSubview(self)
        parent.addSubview(errorLabel)
        addContentSubviews()
        configureCollectionView(cv)
        activateConstraints(parent, cv, errorLabel)
        showSkeletonState()
    }

    func update(with info: ChannelInfo, fallback: String) {
        hideSkeletonState()
        nameLabel.text = info.title.isEmpty ? fallback : info.title
        subscribersLabel.text = [
            info.subscriberCountText, info.videoCountText
        ].compactMap { $0 }.joined(separator: " · ")
        verifiedBadgeView.isHidden = !info.isVerified
        badgeWidthRef?.constant = info.isVerified ? 14 : 0
        loadImage(info.avatarURL, into: avatarView)
        loadImage(info.bannerURL, into: bannerImageView)
    }

    func updateSubscription(title: String, isEnabled: Bool) {
        subscribeButton.setTitle(title, for: .normal)
        subscribeButton.isEnabled = isEnabled
    }

    func applyTheme(isSubscribed: Bool) {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        bannerImageView.backgroundColor = theme.surface
        nameLabel.textColor = theme.primaryText
        subscribersLabel.textColor = theme.secondaryText
        separatorView.backgroundColor = theme.separator
        applyButtonTheme(subscribed: isSubscribed, theme: theme)
    }

    /// Collapses the header as the list scrolls up. Only the height and
    /// the fade move — the inner layout stays put and is clipped away.
    func updateForScroll(_ scrollView: UIScrollView) {
        guard let heightRef
        else {
            return
        }
        let inset = scrollView.adjustedContentInset.top
        let offset = scrollView.contentOffset.y + inset
        let range = expandedHeight - collapsedHeight
        let progress = min(max(offset / range, 0), 1)
        let ht = max(collapsedHeight, expandedHeight - offset)
        heightRef.constant = ht
        isHidden = ht <= 0
        applyScrollAlpha(progress)
    }

    func showSkeletonState() {
        bannerImageView.showSkeleton()
        avatarView.showSkeleton()
        setContentVisible(false)
    }

    func hideSkeletonState() {
        bannerImageView.hideSkeleton()
        avatarView.hideSkeleton()
        setContentVisible(true)
    }

    // MARK: - Private Setup

    private func configureBanner() {
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerImageView)
        bannerOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        bannerOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerOverlay)
        avatarView.layer.cornerRadius = avatarSize / 2
        avatarView.layer.borderWidth = 2
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLabels() {
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            verifiedBadgeView.image = UIImage(
                systemName: "checkmark.seal.fill"
            )
        }
        verifiedBadgeView.tintColor = .systemBlue
        verifiedBadgeView.contentMode = .scaleAspectFit
        verifiedBadgeView.isHidden = true
        verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = false
        subscribersLabel.font = .systemFont(ofSize: 13)
        subscribersLabel.numberOfLines = 1
        subscribersLabel.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        subscribersLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureButtonAndSeparator() {
        subscribeButton.titleLabel?.font = .systemFont(
            ofSize: 14, weight: .semibold
        )
        subscribeButton.layer.cornerRadius = 16
        subscribeButton.contentEdgeInsets = UIEdgeInsets(
            top: 8, left: 16, bottom: 8, right: 16
        )
        subscribeButton.setContentCompressionResistancePriority(
            .required, for: .horizontal
        )
        subscribeButton.isEnabled = !OAuthClient.shared.isAnonymous
        subscribeButton.translatesAutoresizingMaskIntoConstraints = false
        separatorView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func addContentSubviews() {
        [
            avatarView, nameLabel, verifiedBadgeView,
            subscribersLabel, subscribeButton, separatorView,
            nameSkeleton, subsSkeleton, btnSkeleton
        ].forEach { addSubview($0) }
    }

    // MARK: - Private Helpers

    private func applyScrollAlpha(_ progress: CGFloat) {
        let fade = max(0, 1 - progress * 1.4)
        avatarView.alpha = fade
        nameLabel.alpha = fade
        verifiedBadgeView.alpha = fade
        subscribersLabel.alpha = fade
        subscribeButton.alpha = fade
        separatorView.alpha = fade
        bannerImageView.alpha = max(0, 1 - progress * 2.0)
        bannerOverlay.alpha = bannerImageView.alpha
    }

    private func applyButtonTheme(
        subscribed: Bool,
        theme: ThemeManager
    ) {
        avatarView.layer.borderColor = theme.background.cgColor
        if subscribed {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(
                theme.primaryText, for: .normal
            )
        } else {
            subscribeButton.backgroundColor = theme.accent
            subscribeButton.setTitleColor(.white, for: .normal)
        }
    }

    private func setContentVisible(_ visible: Bool) {
        nameLabel.isHidden = !visible
        subscribersLabel.isHidden = !visible
        subscribeButton.isHidden = !visible
        if !visible { verifiedBadgeView.isHidden = true }
        nameSkeleton.isHidden = visible
        subsSkeleton.isHidden = visible
        btnSkeleton.isHidden = visible
    }

    private func loadImage(
        _ urlString: String?,
        into imageView: ThumbnailImageView
    ) {
        guard let urlString, let url = URL(string: urlString)
        else {
            return
        }
        imageView.setImage(url: url)
    }
}
