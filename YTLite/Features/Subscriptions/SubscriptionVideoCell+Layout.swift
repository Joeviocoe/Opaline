import UIKit

// MARK: - Layout

extension SubscriptionVideoCell {
    /// UIKit measures a self-sizing row twice — once through
    /// `systemLayoutSizeFitting` and again in `layoutSubviews` — so this
    /// caches the text measurement per cell. Keyed by width: the three
    /// callers derive `textW` differently, and an unkeyed cache would hand
    /// one of them a height measured for someone else's width.
    private func computeTitleHeight(for width: CGFloat) -> CGFloat {
        if cachedTitleHeight > 0, cachedTitleWidth == width {
            return cachedTitleHeight
        }
        let height = titleLabel.sizeThatFits(CGSize(width: width, height: 52)).height
        cachedTitleHeight = min(height, 40)
        cachedTitleWidth = width
        return cachedTitleHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        if width > 500 {
            layoutHorizontal(width: width)
        } else {
            layoutVertical(width: width)
        }
        layoutProgress()
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

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width
        if width > 500 {
            return CGSize(width: width, height: 220)
        } else {
            let thumbH = (width * 9.0 / 16.0).rounded()
            let textW = width - 12 - 36 - 10 - 12 - 36
            let titleH = computeTitleHeight(for: textW)
            return CGSize(width: width, height: thumbH + 10 + titleH + 4 + 16 + 2 + 16 + 12)
        }
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width > 10 ? targetSize.width : bounds.width
        return sizeThatFits(CGSize(width: width, height: 0))
    }

    /// iPad / wide: thumbnail left, text right — matches original subscriptions style
    private func layoutHorizontal(width: CGFloat) {
        let height: CGFloat = 220
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbH: CGFloat = height - vPad * 2
        let thumbW: CGFloat = (thumbH * 16.0 / 9.0).rounded()

        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let dx = thumbnail.bounds.width - dW - 4
            let dy = thumbnail.bounds.height - 22
            durationLabel.frame = CGRect(x: dx, y: dy, width: dW, height: 18)
        }

        let avatarSz: CGFloat = 36
        let textX = thumbnail.frame.maxX + hPad
        let menuButtonW: CGFloat = 36
        let textW = width - textX - hPad - menuButtonW

        let titleH = computeTitleHeight(for: textW)
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: titleH)
        // titleH collapses to ~20 on single-line titles; keep a tappable box.
        menuButton.frame = CGRect(
            x: textX + textW, y: vPad, width: menuButtonW, height: max(titleH, 36)
        )

        let afterTitle = titleLabel.frame.maxY + 8
        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
        let labelX = textX + avatarSz + 10
        let labelW = width - labelX - hPad
        let chanY = afterTitle + (avatarSz - 15) / 2
        channelLabel.frame = CGRect(x: labelX, y: chanY, width: labelW, height: 15)
        let dateY = channelAvatarView.frame.maxY + 6
        dateLabel.frame = CGRect(x: textX, y: dateY, width: textW, height: 15)
    }

    /// iPhone / slide-over / narrow: thumbnail full-width on top, text below
    private func layoutVertical(width: CGFloat) {
        let thumbH = (width * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: 0, y: 0, width: width, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let dx = thumbnail.bounds.width - dW - 6
            let dy = thumbnail.bounds.height - 24
            durationLabel.frame = CGRect(x: dx, y: dy, width: dW, height: 18)
        }

        let avatarSz: CGFloat = 36
        let hPad: CGFloat = 12
        let avatarX: CGFloat = hPad
        let textX = avatarX + avatarSz + 10
        let menuButtonW: CGFloat = 36
        let textW = width - textX - hPad - menuButtonW

        channelAvatarView.isHidden = false
        let avatarY = thumbH + 10
        channelAvatarView.frame = CGRect(x: avatarX, y: avatarY, width: avatarSz, height: avatarSz)

        let titleH = computeTitleHeight(for: textW)
        titleLabel.frame = CGRect(x: textX, y: thumbH + 10, width: textW, height: titleH)
        menuButton.frame = CGRect(
            x: textX + textW, y: thumbH + 10, width: menuButtonW, height: max(titleH, 36)
        )

        let channelTop = titleLabel.frame.maxY + 4
        channelLabel.frame = CGRect(x: textX, y: channelTop, width: textW, height: 16)
        dateLabel.frame = CGRect(x: textX, y: channelLabel.frame.maxY + 2, width: textW, height: 16)
    }
}
