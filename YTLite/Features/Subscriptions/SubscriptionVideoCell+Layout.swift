import UIKit

// MARK: - Layout

extension SubscriptionVideoCell {
    private static let titleFont = UIFont.systemFont(ofSize: 14, weight: .medium)
    private static let titleHeightMemoLimit = 300
    private static var titleHeightMemo: [String: CGFloat] = [:]

    /// Pure text measurement — the single formula both the cell (which has
    /// a live label to ask) and table view delegates (which don't) use, so
    /// row heights can never drift from what `layoutSubviews` actually
    /// draws.
    ///
    /// The cap reproduces `titleLabel.numberOfLines = 2`: `boundingRect`
    /// does not know about it and happily reports three lines for a long
    /// title, which `UILabel` would then truncate — leaving the row taller
    /// than the text it shows.
    static func measuredTitleHeight(text: String, width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else {
            return 0
        }
        let bounds = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont],
            context: nil
        )
        let twoLines = (titleFont.lineHeight * 2).rounded(.up)
        return min(bounds.height.rounded(.up), twoLines)
    }

    /// Row height for the vertical (narrow) layout as a pure function of
    /// (width, title) — mirrors `sizeThatFits` exactly so delegates can
    /// compute `heightForRowAt` without a live cell. Memoized per
    /// (title, width): table view delegates re-ask this every scroll pass.
    static func rowHeight(forWidth width: CGFloat, title: String) -> CGFloat {
        guard width <= 500 else {
            return 220
        }
        let textW = width - 12 - 36 - 10 - 12 - 36
        let key = "\(Int(textW))|\(title)"
        let titleH: CGFloat
        if let cached = titleHeightMemo[key] {
            titleH = cached
        } else {
            titleH = measuredTitleHeight(text: title, width: textW)
            if titleHeightMemo.count >= titleHeightMemoLimit {
                titleHeightMemo.removeAll()
            }
            titleHeightMemo[key] = titleH
        }
        let thumbH = (width * 9.0 / 16.0).rounded()
        return thumbH + 10 + titleH + 4 + 16 + 2 + 16 + 12
    }

    /// UIKit measures a self-sizing row twice — once through
    /// `systemLayoutSizeFitting` and again in `layoutSubviews` — so this
    /// caches the text measurement per cell. Keyed by width: the three
    /// callers derive `textW` differently, and an unkeyed cache would hand
    /// one of them a height measured for someone else's width.
    private func computeTitleHeight(for width: CGFloat) -> CGFloat {
        if cachedTitleHeight > 0, cachedTitleWidth == width {
            return cachedTitleHeight
        }
        let height = Self.measuredTitleHeight(text: titleLabel.text ?? "", width: width)
        cachedTitleHeight = height
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
        let height = Self.rowHeight(forWidth: width, title: titleLabel.text ?? "")
        return CGSize(width: width, height: height)
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
