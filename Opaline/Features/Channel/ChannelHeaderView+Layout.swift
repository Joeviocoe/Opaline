import UIKit

extension ChannelHeaderView {
    /// Horizontal layout: banner strip, then one row of
    /// avatar + name/stats + subscribe button.
    func activateConstraints(
        _ parent: UIView,
        _ cv: UICollectionView,
        _ errLabel: UILabel
    ) {
        heightRef = heightAnchor.constraint(
            equalToConstant: expandedHeight
        )
        var all = frameConstraints(parent)
        all += bannerConstraints()
        all += avatarAndButtonConstraints()
        all += textConstraints()
        all += skeletonConstraints()
        all += outerConstraints(parent, cv, errLabel)
        NSLayoutConstraint.activate(all)
    }

    /// The list scrolls under the header, so its top inset is the
    /// header's expanded height.
    func configureCollectionView(_ cv: UICollectionView) {
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.autoresizingMask = []
        cv.contentInset = UIEdgeInsets(
            top: expandedHeight, left: 0, bottom: 0, right: 0
        )
        cv.scrollIndicatorInsets = UIEdgeInsets(
            top: expandedHeight, left: 0, bottom: 0, right: 0
        )
        cv.setContentOffset(
            CGPoint(x: 0, y: -expandedHeight), animated: false
        )
    }

    private func frameConstraints(
        _ parent: UIView
    ) -> [NSLayoutConstraint] {
        guard let heightRef = heightRef
        else {
            return []
        }
        let safe = parent.safeAreaLayoutGuide
        return [
            topAnchor.constraint(equalTo: safe.topAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            heightRef
        ]
    }

    private func bannerConstraints() -> [NSLayoutConstraint] {
        let biv = bannerImageView
        let bov = bannerOverlay
        let sv = separatorView
        return [
            biv.topAnchor.constraint(equalTo: topAnchor),
            biv.leadingAnchor.constraint(equalTo: leadingAnchor),
            biv.trailingAnchor.constraint(equalTo: trailingAnchor),
            biv.heightAnchor.constraint(equalToConstant: bannerHeight),
            bov.topAnchor.constraint(equalTo: biv.topAnchor),
            bov.leadingAnchor.constraint(equalTo: biv.leadingAnchor),
            bov.trailingAnchor.constraint(equalTo: biv.trailingAnchor),
            bov.bottomAnchor.constraint(equalTo: biv.bottomAnchor),
            sv.leadingAnchor.constraint(equalTo: leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: trailingAnchor),
            sv.heightAnchor.constraint(equalToConstant: 1),
            sv.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
    }

    /// The avatar straddles the banner edge; the button lines up with
    /// its bottom, next to the stats.
    private func avatarAndButtonConstraints() -> [NSLayoutConstraint] {
        let av = avatarView
        let sb = subscribeButton
        return [
            av.topAnchor.constraint(
                equalTo: topAnchor,
                constant: bannerHeight - avatarOverlap
            ),
            av.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 16
            ),
            av.widthAnchor.constraint(equalToConstant: avatarSize),
            av.heightAnchor.constraint(equalToConstant: avatarSize),
            sb.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -16
            ),
            sb.bottomAnchor.constraint(equalTo: av.bottomAnchor),
            sb.heightAnchor.constraint(equalToConstant: 32)
        ]
    }

    /// Name and stats sit beside the avatar, aligned to its bottom —
    /// which keeps them clear of the banner above.
    private func textConstraints() -> [NSLayoutConstraint] {
        let nl = nameLabel
        let sl = subscribersLabel
        let vb = verifiedBadgeView
        let textLead = avatarView.trailingAnchor
        let limit = subscribeButton.leadingAnchor
        let badgeWidth = vb.widthAnchor.constraint(equalToConstant: 0)
        badgeWidthRef = badgeWidth
        return [
            nl.leadingAnchor.constraint(equalTo: textLead, constant: 12),
            nl.bottomAnchor.constraint(
                equalTo: sl.topAnchor, constant: -2
            ),
            vb.leadingAnchor.constraint(
                equalTo: nl.trailingAnchor, constant: 4
            ),
            vb.trailingAnchor.constraint(
                lessThanOrEqualTo: limit, constant: -12
            ),
            vb.centerYAnchor.constraint(equalTo: nl.centerYAnchor),
            vb.heightAnchor.constraint(equalToConstant: 14),
            badgeWidth,
            sl.leadingAnchor.constraint(equalTo: textLead, constant: 12),
            sl.bottomAnchor.constraint(
                equalTo: avatarView.bottomAnchor
            ),
            sl.trailingAnchor.constraint(
                lessThanOrEqualTo: limit, constant: -12
            )
        ]
    }

    private func skeletonConstraints() -> [NSLayoutConstraint] {
        let ns = nameSkeleton
        let ss = subsSkeleton
        let bs = btnSkeleton
        let textLead = avatarView.trailingAnchor
        return [
            ns.leadingAnchor.constraint(equalTo: textLead, constant: 12),
            ns.bottomAnchor.constraint(
                equalTo: ss.topAnchor, constant: -6
            ),
            ns.widthAnchor.constraint(equalToConstant: 150),
            ns.heightAnchor.constraint(equalToConstant: 16),
            ss.leadingAnchor.constraint(equalTo: textLead, constant: 12),
            ss.bottomAnchor.constraint(
                equalTo: avatarView.bottomAnchor, constant: -2
            ),
            ss.widthAnchor.constraint(equalToConstant: 100),
            ss.heightAnchor.constraint(equalToConstant: 12),
            bs.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -16
            ),
            bs.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),
            bs.widthAnchor.constraint(equalToConstant: 104),
            bs.heightAnchor.constraint(equalToConstant: 32)
        ]
    }

    private func outerConstraints(
        _ parent: UIView,
        _ cv: UICollectionView,
        _ errLabel: UILabel
    ) -> [NSLayoutConstraint] {
        let safe = parent.safeAreaLayoutGuide
        return [
            cv.topAnchor.constraint(equalTo: safe.topAnchor),
            cv.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            cv.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor
            ),
            cv.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            errLabel.centerXAnchor.constraint(
                equalTo: cv.centerXAnchor
            ),
            errLabel.centerYAnchor.constraint(
                equalTo: cv.centerYAnchor
            ),
            errLabel.leadingAnchor.constraint(
                equalTo: parent.leadingAnchor, constant: 32
            ),
            errLabel.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor, constant: -32
            )
        ]
    }
}
