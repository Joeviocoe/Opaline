import UIKit

// MARK: - Layout

extension SubscriptionVideoCell {
    private static let titleFont = UIFont.systemFont(ofSize: 14, weight: .medium)
    private static let titleHeightMemoLimit = 300
    private static var titleHeightMemo: [String: CGFloat] = [:]

    // Wide-layout geometry, in one place because `rowHeight` and
    // `layoutHorizontal` have to agree exactly — the row is measured by a
    // delegate that has no cell to ask, so any drift shows up as text
    // clipped or floating in dead space.
    static let hPad: CGFloat = 12
    static let vPad: CGFloat = 10
    /// Half the old 200pt: four rows now fit where two did. The row is no
    /// longer a fixed 220 — it follows this, or the text, whichever is
    /// taller.
    static let wideThumbHeight: CGFloat = 100
    static var wideThumbWidth: CGFloat {
        (wideThumbHeight * 16.0 / 9.0).rounded()
    }
    /// Down from 36 with the thumbnail. At 36 the avatar row alone made the
    /// text stack taller than the picture, so the row could not shrink and
    /// halving the thumbnail bought nothing.
    static let avatarSize: CGFloat = 24
    static let menuButtonWidth: CGFloat = 36
    /// One line under the meta text. 13pt against the meta's 12: large
    /// enough to read as its own line rather than a continuation.
    ///
    /// If this grows, grow the box with it — the font's own line height is
    /// ~19pt at 16pt, so the text clips against a 17pt box. This figure also
    /// feeds `rowHeight`, so the row follows.
    static let durationLineHeight: CGFloat = 17

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
    /// `hasDuration` defaults false so a caller that has not been taught
    /// about the duration line still measures a row that fits — the line
    /// only takes space when there is something to put in it, which matters
    /// because the RSS-assembled subscriptions feed has no durations at all
    /// and would otherwise carry 17pt of blank in every row.
    static func rowHeight(
        forWidth width: CGFloat,
        title: String,
        hasDuration: Bool = false
    ) -> CGFloat {
        let durationH = hasDuration ? 2 + durationLineHeight : 0
        guard width <= 500 else {
            return wideRowHeight(
                width: width, title: title, durationH: durationH
            )
        }
        let textW = width - hPad - 36 - 10 - hPad - menuButtonWidth
        let titleH = memoizedTitleHeight(title, width: textW)
        let thumbH = (width * 9.0 / 16.0).rounded()
        return thumbH + 10 + titleH + 4 + 16 + 2 + 16 + durationH + 12
    }

    /// The row is now `max(picture, text)` rather than a fixed 220: with a
    /// 100pt thumbnail a two-line title plus channel, meta and duration is
    /// frequently the taller of the two, and clamping to the picture would
    /// clip it.
    private static func wideRowHeight(
        width: CGFloat, title: String, durationH: CGFloat
    ) -> CGFloat {
        let textX = hPad + wideThumbWidth + hPad
        let textW = width - textX - hPad - menuButtonWidth
        let titleH = memoizedTitleHeight(title, width: textW)
        let textStack = titleH + 4 + avatarSize + 2 + 15 + durationH
        return max(wideThumbHeight, textStack) + vPad * 2
    }

    /// `heightForRowAt` re-asks for every visible row on every scroll pass,
    /// so the text measurement is cached rather than repeated.
    private static func memoizedTitleHeight(
        _ title: String, width: CGFloat
    ) -> CGFloat {
        let key = "\(Int(width))|\(title)"
        if let cached = titleHeightMemo[key] {
            return cached
        }
        let measured = measuredTitleHeight(text: title, width: width)
        if titleHeightMemo.count >= titleHeightMemoLimit {
            titleHeightMemo.removeAll()
        }
        titleHeightMemo[key] = measured
        return measured
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

    /// iPad / wide: thumbnail left, text right. The text column starts from
    /// the thumbnail's trailing edge, so halving the picture moves the whole
    /// stack left with it rather than leaving a gutter.
    private func layoutHorizontal(width: CGFloat) {
        let vPad = Self.vPad
        let hPad = Self.hPad
        let thumbH = Self.wideThumbHeight
        let thumbW = Self.wideThumbWidth

        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)

        let avatarSz = Self.avatarSize
        let textX = thumbnail.frame.maxX + hPad
        let menuButtonW = Self.menuButtonWidth
        let textW = width - textX - hPad - menuButtonW

        let titleH = computeTitleHeight(for: textW)
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: titleH)
        // titleH collapses to ~20 on single-line titles; keep a tappable box.
        menuButton.frame = CGRect(
            x: textX + textW, y: vPad, width: menuButtonW, height: max(titleH, 36)
        )

        let afterTitle = titleLabel.frame.maxY + 4
        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
        let labelX = textX + avatarSz + 8
        let labelW = width - labelX - hPad - menuButtonW
        let chanY = afterTitle + (avatarSz - 15) / 2
        channelLabel.frame = CGRect(x: labelX, y: chanY, width: labelW, height: 15)
        let dateY = channelAvatarView.frame.maxY + 2
        dateLabel.frame = CGRect(x: textX, y: dateY, width: textW, height: 15)
        layoutDurationLine(x: textX, below: dateLabel.frame.maxY, width: textW)
    }

    /// Duration as its own line under the meta, left-aligned with the text
    /// column — not the corner badge it used to be. A 178pt-wide thumbnail
    /// has no room for an overlay that stays legible.
    private func layoutDurationLine(x: CGFloat, below y: CGFloat, width: CGFloat) {
        guard !durationLabel.isHidden else {
            durationLabel.frame = .zero
            return
        }
        durationLabel.frame = CGRect(
            x: x, y: y + 2, width: width, height: Self.durationLineHeight
        )
    }

    /// iPhone / slide-over / narrow: thumbnail full-width on top, text below
    private func layoutVertical(width: CGFloat) {
        let thumbH = (width * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: 0, y: 0, width: width, height: thumbH)

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
        // Same treatment as the wide layout, so the two never disagree about
        // where duration lives.
        layoutDurationLine(x: textX, below: dateLabel.frame.maxY, width: textW)
    }
}
