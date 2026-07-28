import UIKit

extension WatchViewController {
    func updateLayoutForSize(_ size: CGSize? = nil) {
        // While in fullscreen the player view lives in the window, not in our
        // view hierarchy — skip layout until the user exits fullscreen.
        guard fullscreenSnapshot == nil else {
            return
        }
        let resolved = size ?? view.bounds.size
        let isLandscape = resolved.width > resolved.height
        if isLandscape {
            activateLandscapeLayout()
        } else {
            activatePortraitLayout()
        }
        relatedCollectionView.backgroundColor = ThemeManager.shared.background
        let expected = isLandscape ? landscapeRelatedLayout : portraitRelatedLayout
        if !isLandscape { relatedCollectionView.alpha = 1 }
        view.bringSubviewToFront(playerContainer)
        view.bringSubviewToFront(sidebarContainer)
        if let sv = relatedCollectionView.superview {
            sv.setNeedsLayout()
            sv.layoutIfNeeded()
        }
        if relatedCollectionView.bounds.width > 0 {
            updateRelatedLayout(isLandscape: isLandscape, containerSize: resolved)
        }
        // Swap last: applying a layout that still carries the item size from
        // the previous width makes the flow layout complain.
        if relatedCollectionView.collectionViewLayout !== expected {
            relatedCollectionView.setCollectionViewLayout(expected, animated: false)
        }
    }

    func activateLandscapeLayout() {
        scrollTrailingConstraint?.isActive = false
        scrollToSidebarConstraint?.isActive = true
        sidebarTopConstraint?.isActive = true
        sidebarTrailingConstraint?.isActive = true
        sidebarBottomConstraint?.isActive = true
        sidebarWidthConstraint?.isActive = true
        sidebarContainer.isHidden = false
        playerTrailingConstraint?.isActive = false
        playerToSidebarConstraint?.isActive = true
        moveRelatedCollection(toLandscape: true)
        bottomCommentsConstraint?.isActive = true
    }

    func activatePortraitLayout() {
        bottomCommentsConstraint?.isActive = false
        scrollToSidebarConstraint?.isActive = false
        scrollTrailingConstraint?.isActive = true
        sidebarTopConstraint?.isActive = false
        sidebarTrailingConstraint?.isActive = false
        sidebarBottomConstraint?.isActive = false
        sidebarWidthConstraint?.isActive = false
        sidebarContainer.isHidden = true
        playerToSidebarConstraint?.isActive = false
        playerTrailingConstraint?.isActive = true
        moveRelatedCollection(toLandscape: false)
        // Force multi-line labels to re-wrap at the new (wider) portrait width.
        metaLabel.invalidateIntrinsicContentSize()
        metaLabel.setNeedsLayout()
    }

    func updateRelatedLayout(
        isLandscape: Bool,
        containerSize: CGSize? = nil
    ) {
        let layout = isLandscape
            ? landscapeRelatedLayout
            : portraitRelatedLayout
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = isLandscape ? 0 : 6
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: 8, bottom: 12, right: 8
        )
        let size = computeItemSize(
            layout: layout,
            isLandscape: isLandscape,
            containerSize: containerSize
        )
        if layout.itemSize != size {
            layout.itemSize = size
        }
        updateRelatedHeight(
            layout: layout,
            isLandscape: isLandscape,
            itemHeight: size.height
        )
        layout.invalidateLayout()
    }

    func computeItemSize(
        layout: UICollectionViewFlowLayout,
        isLandscape: Bool,
        containerSize: CGSize?
    )
        -> CGSize {
        let cols: CGFloat = isLandscape ? 1 : 2
        let inset = layout.sectionInset.left
            + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing
            * (cols - 1)
        let baseWidth: CGFloat = if let containerSize {
            isLandscape
                ? (sidebarWidthConstraint?.constant ?? 0)
                : containerSize.width
        } else {
            relatedCollectionView.bounds.width
        }
        // The collection view can still be at its pre-transition width — iOS
        // also resizes the app off-screen for the multitasking snapshot — and
        // items wider than it make the flow layout complain. The transition's
        // completion pass re-runs this against the settled bounds.
        let actual = relatedCollectionView.bounds.width
        let width = actual > 0 ? min(baseWidth, actual) : baseWidth
        let available = max(width - inset - spacing, 120)
        let itemWidth = floor(available / cols)
        let itemHeight = itemWidth * (9.0 / 16.0) + 92
        return CGSize(width: itemWidth, height: itemHeight)
    }

    func updateRelatedHeight(
        layout: UICollectionViewFlowLayout,
        isLandscape: Bool,
        itemHeight: CGFloat
    ) {
        let cols: CGFloat = isLandscape ? 1 : 2
        let si = layout.sectionInset
        let headerHeight: CGFloat = isPlaylistMode ? 32 : 0
        let playlistCount = CGFloat(
            isPlaylistMode ? queue.videos.count : 0
        )
        let relatedCount = CGFloat(
            visibleRelatedVideos.count
        )
        func sectionHeight(_ count: CGFloat) -> CGFloat {
            let rows = count == 0 ? 0 : ceil(count / cols)
            return rows == 0 ? 0 : si.top + si.bottom
                + rows * itemHeight
                + max(0, rows - 1)
                * layout.minimumLineSpacing
        }
        let playlistHeight = sectionHeight(playlistCount)
        let relatedHeight = sectionHeight(relatedCount)
        let totalSections = isPlaylistMode ? 2 : 1
        let totalHeaders = CGFloat(totalSections - 1)
            * headerHeight
        let total = playlistHeight
            + relatedHeight + totalHeaders
        let desired = isLandscape ? 0 : total
        if relatedHeightConstraint?.constant != desired {
            relatedHeightConstraint?.constant = desired
        }
    }

    func moveRelatedCollection(toLandscape isLandscape: Bool) {
        guard isShowingLandscapeRelated != isLandscape else {
            return
        }
        let old = isLandscape
            ? relatedPortraitConstraints
            : relatedLandscapeConstraints
        NSLayoutConstraint.deactivate(old)
        relatedCollectionView.removeFromSuperview()
        if isLandscape {
            moveLandscapeRelated()
        } else {
            relatedCollectionView.isScrollEnabled = false
            contentView.addSubview(relatedCollectionView)
            NSLayoutConstraint.activate(relatedPortraitConstraints)
        }
        isShowingLandscapeRelated = isLandscape
    }

    private func moveLandscapeRelated() {
        relatedCollectionView.isScrollEnabled = true
        // Reset any scroll offset carried over from portrait so the first video is
        // fully visible at the top of the sidebar when entering landscape.
        relatedCollectionView.setContentOffset(.zero, animated: false)
        sidebarContainer.addSubview(relatedCollectionView)
        let rv = relatedCollectionView
        let sc = sidebarContainer
        relatedLandscapeConstraints = [
            rv.topAnchor.constraint(equalTo: sc.topAnchor),
            rv.leadingAnchor.constraint(equalTo: sc.leadingAnchor),
            rv.trailingAnchor.constraint(equalTo: sc.trailingAnchor),
            rv.bottomAnchor.constraint(equalTo: sc.bottomAnchor)
        ]
        NSLayoutConstraint.activate(relatedLandscapeConstraints)
    }
}
