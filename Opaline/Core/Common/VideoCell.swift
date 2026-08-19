// swiftlint:disable file_length
import UIKit

class VideoCell: UICollectionViewCell {
    static let reuseId = "VideoCell"

    private static let avatarSize: CGFloat = 32
    private static let hPad: CGFloat = 6
    private static let avatarGap: CGFloat = 10
    private static let vPadAfterThumb: CGFloat = 8

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = makeBadgeLabel()
    private let mixBadge = makeBadgeLabel()
    private let downloadBadge = DownloadBadgeView()
    private let downloadBar = DownloadProgressBar()
    private let liveBadgeView = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var watchFraction: CGFloat = 0
    private let channelAvatarView = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let metaLabel = UILabel()
    private let menuButton = UIButton(type: .system)
    private var representedChannelId: String?
    private var cachedTitleHeight: CGFloat = 0
    var onChannelTap: (() -> Void)?
    var onMenuTap: ((UIView) -> Void)?

    /// Force grid layout regardless of cell width.
    /// Off inside the queue panel: there every row is part of a queue, so
    /// the marker says nothing and only costs the duration its place.
    var showsMixBadge = true
    var forceGridLayout: Bool = false {
        didSet {
            if oldValue != forceGridLayout { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let cellWidth = contentView.bounds.width
        if !forceGridLayout && cellWidth > 350 {
            layoutHorizontal(cellWidth: cellWidth)
        } else {
            layoutGrid(cellWidth: cellWidth)
        }
        thumbnail.maxPixelSize = ThumbnailSizing.pixelSize(
            forDisplayWidth: thumbnail.bounds.width,
            scale: window?.screen.scale ?? UIScreen.main.scale
        )
        layoutProgress()
        layoutMixBadge()
    }

    /// Sits where the duration would, which is why the duration is hidden
    /// while it shows: this card carries a mix, so opening it starts a queue
    /// rather than a single video, and the card otherwise looks like any
    /// other.
    private func layoutMixBadge() {
        guard !mixBadge.isHidden else {
            return
        }
        let width = max(34, mixBadge.intrinsicContentSize.width + 8)
        let isGrid = forceGridLayout || contentView.bounds.width <= 350
        mixBadge.frame = CGRect(
            x: thumbnail.bounds.width - width - (isGrid ? 6 : 4),
            y: thumbnail.bounds.height - (isGrid ? 24 : 22),
            width: width,
            height: 18
        )
    }

    private func layoutProgress() {
        let barH: CGFloat = 3
        let thumbW = thumbnail.bounds.width
        let thumbH = thumbnail.bounds.height
        guard thumbW > 0, thumbH > 0 else {
            return
        }
        let barY = thumbH - barH
        progressTrack.frame = CGRect(x: 0, y: barY, width: thumbW, height: barH)
        progressFill.frame = CGRect(x: 0, y: barY, width: thumbW * watchFraction, height: barH)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hideSkeleton()
        representedChannelId = nil
        thumbnail.cancel()
        channelAvatarView.cancel()
        titleLabel.text = nil
        channelLabel.text = nil
        metaLabel.text = nil
        durationLabel.text = nil
        durationLabel.isHidden = true
        mixBadge.isHidden = true
        liveBadgeView.isHidden = true
        channelAvatarView.isHidden = false
        watchFraction = 0
        progressTrack.isHidden = true
        progressFill.isHidden = true
        onChannelTap = nil
        onMenuTap = nil
    }
}

// MARK: - Setup

extension VideoCell {
    /// Both corner plates on the artwork are the same chip.
    private static func makeBadgeLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = ThemeManager.shared.durationBackground
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        label.textAlignment = .center
        return label
    }

    private func showDownloadState(of videoId: String?) {
        downloadBadge.configure(videoId: videoId)
        downloadBar.configure(videoId: videoId)
    }

    private func setupUI() {
        thumbnail.layer.cornerRadius = 4
        thumbnail.layer.masksToBounds = true
        contentView.addSubview(thumbnail)

        progressTrack.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        progressTrack.isHidden = true
        thumbnail.addSubview(progressTrack)
        progressFill.backgroundColor = UIColor(
            red: 1, green: 0, blue: 0, alpha: 1
        )
        thumbnail.addSubview(progressFill)

        thumbnail.addSubview(durationLabel)
        mixBadge.text = " \("player.related.mix".localized) "
        mixBadge.isHidden = true
        thumbnail.addSubview(mixBadge)

        liveBadgeView.text = "● LIVE"
        liveBadgeView.textColor = .white
        liveBadgeView.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        liveBadgeView.backgroundColor = ThemeManager.shared.liveBadgeBackground
        liveBadgeView.layer.cornerRadius = 3
        liveBadgeView.layer.masksToBounds = true
        liveBadgeView.textAlignment = .center
        liveBadgeView.isHidden = true
        thumbnail.addSubview(liveBadgeView)

        downloadBadge.pin(toThumbnail: thumbnail)
        downloadBar.pin(toThumbnail: thumbnail)

        setupInfoArea()
        applyTheme()
    }

    private func setupInfoArea() {
        channelAvatarView.layer.cornerRadius = VideoCell.avatarSize / 2
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.isUserInteractionEnabled = true
        channelAvatarView.maxPixelSize = 96
        contentView.addSubview(channelAvatarView)
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)
        channelLabel.font = UIFont.systemFont(ofSize: 11)
        channelLabel.isUserInteractionEnabled = true
        contentView.addSubview(channelLabel)
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        contentView.addSubview(metaLabel)
        menuButton.setImage(resizedNavBarIcon("icon_ellipsis_vertical", size: 16), for: .normal)
        // Keeps the 40pt hit box while the glyph itself sits near the card edge.
        menuButton.contentHorizontalAlignment = .right
        menuButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        menuButton.addTarget(self, action: #selector(handleMenuTap), for: .touchUpInside)
        contentView.addSubview(menuButton)
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelAvatarView.addGestureRecognizer(avatarTap)
        let labelTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelLabel.addGestureRecognizer(labelTap)
    }
}

// MARK: - Layout

extension VideoCell {
    private func computeTitleHeight(for width: CGFloat) -> CGFloat {
        if cachedTitleHeight > 0 {
            return cachedTitleHeight
        }
        let height = titleLabel.sizeThatFits(
            CGSize(width: width, height: 60)
        ).height
        cachedTitleHeight = min(height, 52)
        return cachedTitleHeight
    }

    private func layoutHorizontal(cellWidth: CGFloat) {
        let cellHeight = contentView.bounds.height
        if cellHeight >= 150 {
            layoutHorizontalTall(cellWidth: cellWidth, cellHeight: cellHeight)
        } else {
            layoutHorizontalCompact(cellWidth: cellWidth)
        }
    }

    private func layoutHorizontalTall(cellWidth: CGFloat, cellHeight: CGFloat) {
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbH = cellHeight - vPad * 2
        let thumbW = (thumbH * 16.0 / 9.0).rounded()
        let clampedW = min(thumbW, cellWidth * 0.55)
        let clampedH = (clampedW * 9.0 / 16.0).rounded()
        let thumbY = (cellHeight - clampedH) / 2
        thumbnail.frame = CGRect(x: hPad, y: thumbY, width: clampedW, height: clampedH)
        layoutBadgesForHorizontal()
        let avatarSz: CGFloat = 32
        let textX = thumbnail.frame.maxX + hPad
        let textW = cellWidth - textX - hPad
        let titleW = textW - 40
        let titleH = computeTitleHeight(for: titleW)
        titleLabel.frame = CGRect(x: textX, y: vPad, width: titleW, height: titleH)
        menuButton.frame = CGRect(x: cellWidth - 40, y: vPad, width: 40, height: 40)
        let afterTitle = titleLabel.frame.maxY + 8
        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
        let labelX = textX + avatarSz + 8
        let labelW = cellWidth - labelX - hPad
        let channelY = afterTitle + (avatarSz - 14) / 2
        channelLabel.frame = CGRect(x: labelX, y: channelY, width: labelW, height: 14)
        let metaY = channelAvatarView.frame.maxY + 6
        metaLabel.frame = CGRect(x: textX, y: metaY, width: textW, height: 14)
    }

    /// Both badges are subviews of the thumbnail, so they are placed in its
    /// bounds — measured against the cell instead they slid out past the
    /// artwork's right edge and were clipped mid-digit.
    private func layoutBadgesForHorizontal() {
        let thumbW = thumbnail.bounds.width
        let thumbH = thumbnail.bounds.height
        if !durationLabel.isHidden {
            let badgeW = max(36, durationLabel.intrinsicContentSize.width + 8)
            durationLabel.frame = CGRect(
                x: thumbW - badgeW - 4, y: thumbH - 22, width: badgeW, height: 18
            )
        }
        if !liveBadgeView.isHidden {
            let badgeW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
            liveBadgeView.frame = CGRect(
                x: thumbW - badgeW - 4, y: thumbH - 22, width: badgeW, height: 14
            )
        }
    }

    private func layoutHorizontalCompact(cellWidth: CGFloat) {
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbW: CGFloat = 160
        let thumbH = (thumbW * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)
        layoutBadgesForHorizontal()
        channelAvatarView.isHidden = true
        let textX = thumbnail.frame.maxX + hPad
        let textW = cellWidth - textX - hPad
        let titleW = textW - 40
        let titleH = computeTitleHeight(for: titleW)
        titleLabel.frame = CGRect(x: textX, y: vPad, width: titleW, height: titleH)
        menuButton.frame = CGRect(x: cellWidth - 40, y: vPad, width: 40, height: 40)
        let channelY = titleLabel.frame.maxY + 4
        channelLabel.frame = CGRect(x: textX, y: channelY, width: textW, height: 14)
        let metaY = channelLabel.frame.maxY + 4
        metaLabel.frame = CGRect(x: textX, y: metaY, width: textW, height: 14)
    }

    private func layoutGrid(cellWidth: CGFloat) {
        let thumbH = (cellWidth * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: 0, y: 0, width: cellWidth, height: thumbH)
        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let dx = cellWidth - dW - 6
            durationLabel.frame = CGRect(x: dx, y: thumbH - 24, width: dW, height: 18)
        }
        if !liveBadgeView.isHidden {
            let lW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
            let lx = cellWidth - lW - 6
            liveBadgeView.frame = CGRect(x: lx, y: thumbH - 22, width: lW, height: 14)
        }
        let hp = VideoCell.hPad
        let avatarSz: CGFloat = channelAvatarView.isHidden ? 0 : VideoCell.avatarSize
        let avatarX: CGFloat = hp
        let textX = avatarSz > 0 ? avatarX + avatarSz + VideoCell.avatarGap : hp
        let textW = cellWidth - textX - hp
        let avatarY = thumbH + VideoCell.vPadAfterThumb
        if !channelAvatarView.isHidden {
            let sz = avatarSz
            channelAvatarView.frame = CGRect(x: avatarX, y: avatarY, width: sz, height: sz)
        }
        let titleTop = thumbH + VideoCell.hPad
        let titleH = computeTitleHeight(for: textW - 40)
        titleLabel.frame = CGRect(x: textX, y: titleTop, width: textW - 40, height: titleH)
        menuButton.frame = CGRect(x: cellWidth - 40, y: titleTop, width: 40, height: 40)
        let channelTop = titleLabel.frame.maxY + 2
        channelLabel.frame = CGRect(x: textX, y: channelTop, width: textW, height: 14)
        let metaTop = channelLabel.frame.maxY + 2
        metaLabel.frame = CGRect(x: textX, y: metaTop, width: textW, height: 14)
    }
}

// MARK: - Actions & Theming

extension VideoCell {
    @objc
    private func handleChannelTap() {
        onChannelTap?()
    }

    @objc
    private func handleMenuTap() {
        // Haptic only: the cell lays its subviews out by frame, which fights
        // the transform `Feedback.pop` animates.
        Feedback.tap()
        onMenuTap?(menuButton)
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.surface
        titleLabel.textColor = theme.primaryText
        channelLabel.textColor = theme.secondaryText
        metaLabel.textColor = theme.secondaryText
        menuButton.tintColor = theme.secondaryText
    }
}

// MARK: - Configuration

extension VideoCell {
    func configureSkeleton() {
        showDownloadState(of: nil)
        hideSkeleton()
        titleLabel.text = nil
        channelLabel.text = nil
        metaLabel.text = nil
        thumbnail.image = nil
        channelAvatarView.image = nil
        durationLabel.isHidden = true
        menuButton.isHidden = true
        contentView.showSkeleton()
    }

    private func loadThumbnail(for video: Video) {
        guard let url = URL(string: video.thumbnailURL) else {
            return
        }
        thumbnail.setImage(
            url: url,
            videoId: video.isShort ? nil : video.id
        )
    }

    func configure(with video: Video) {
        showDownloadState(of: video.id)
        hideSkeleton()
        menuButton.isHidden = false
        representedChannelId = video.channelId
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        metaLabel.text = VideoCardHelper.metaText(
            viewCount: video.viewCount,
            publishedAt: video.publishedAt
        )
        VideoCardHelper.loadChannelAvatar(
            for: video,
            into: channelAvatarView
        ) { [weak self] in
            self?.representedChannelId == video.channelId
        }
        VideoCardHelper.configureBadges(
            video: video,
            durationLabel: durationLabel,
            liveBadgeView: liveBadgeView,
            mixBadge: showsMixBadge ? mixBadge : nil
        )
        loadThumbnail(for: video)
        applyWatchProgress(for: video)
        cachedTitleHeight = 0
        setNeedsLayout()
    }

    /// Nothing for a card that opens a queue: those play from the start, so
    /// a bar from some earlier viewing promises a resume that will not
    /// happen.
    private func applyWatchProgress(for video: Video) {
        if video.playlistId == nil,
           let prog = WatchProgressStore.shared.progress(
               forVideoId: video.id
           ), prog.shouldShow {
            watchFraction = CGFloat(prog.fraction)
            progressTrack.isHidden = false
            progressFill.isHidden = false
        } else {
            watchFraction = 0
            progressTrack.isHidden = true
            progressFill.isHidden = true
        }
    }
}
