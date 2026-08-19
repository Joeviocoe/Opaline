import UIKit

/// What the sliding panel is showing.
enum PlayerSheetKind {
    case comments
    case queue
}

/// Presentation for the sliding panel (`PlayerSheetView`), whichever of the
/// two things is in it — comments or the queue.
/// Portrait: a draggable overlay added directly to `view`, pinned above the
/// player so it keeps playing underneath; two detents (resting / expanded),
/// dragging past resting dismisses it. Landscape: dropped into
/// `sidebarContainer` in place of the related list, no drag — there is
/// nowhere to drag to. Rotating while open reparents rather than stranding it.
extension WatchViewController {
    /// How far past the resting position a released drag has to be, going
    /// down, before it dismisses instead of snapping back.
    private static let dismissSlop: CGFloat = 24
    /// Flick speed (pt/s) past which velocity picks the snap target instead
    /// of position alone.
    private static let flingVelocity: CGFloat = 600

    var isSheetExpanded: Bool {
        presentedSheet != nil
    }

    var isCommentsExpanded: Bool {
        presentedSheet == .comments
    }

    /// How far the panel travels to be fully off-screen — the sidebar's own
    /// height in landscape, the whole view in portrait.
    private var sheetOffscreenConstant: CGFloat {
        sheetSlot.isLandscape
            ? sidebarContainer.bounds.height
            : view.bounds.height
    }

    // MARK: - Present / dismiss

    /// `content` is retained for the whole presentation, including the
    /// dismiss animation that runs after `presentedSheet` has been cleared.
    func presentSheet(_ kind: PlayerSheetKind, content: PlayerSheetView) {
        guard presentedSheet != kind else {
            return
        }
        // Swapping one panel for the other: the one on screen has to leave
        // the hierarchy first, or `detachSheet` later looks at the new view
        // and strands the old one on top of everything.
        if sheetView !== content {
            sheetView?.isHidden = true
            detachSheet()
        }
        presentedSheet = kind
        sheetView = content
        updateQueueBar()
        view.setNeedsLayout()
        // Layout first, animate second. The other order let `layoutSheet`
        // assign the panel's final offset outside the animation block, so
        // opening snapped into place while closing animated.
        updateLayoutForSize()
        let isLandscape = view.bounds.width > view.bounds.height
        attachSheet(isLandscape: isLandscape)
        content.isHidden = false
        // `layoutIfNeeded` runs a layout pass, which reaches
        // `layoutSheet` and would put the panel straight at its
        // detent — leaving the animation below nothing to travel. Pinning
        // the offset keeps the starting position off-screen.
        isSheetOffsetPinned = true
        sheetTopConstraint?.constant = sheetOffscreenConstant
        view.layoutIfNeeded()
        isSheetOffsetPinned = false
        animateSheet(toExpandedDetent: false)
    }

    func collapseSheet() {
        guard presentedSheet != nil else {
            return
        }
        presentedSheet = nil
        updateQueueBar()
        view.setNeedsLayout()
        updateLayoutForSize()
        dismissSheet()
    }

    private func dismissSheet() {
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: .curveEaseIn,
            animations: {
                self.sheetTopConstraint?.constant =
                    self.sheetOffscreenConstant
                self.view.layoutIfNeeded()
            },
            completion: { [weak self] _ in
                guard let self, !self.isSheetExpanded else {
                    return
                }
                self.sheetView?.isHidden = true
                self.detachSheet()
                self.sheetView = nil
                self.relatedCollectionView.isHidden = false
            }
        )
    }

    /// Called on every layout pass (including mid-rotation) so the panel
    /// never gets stranded in the wrong parent or at a stale offset.
    func layoutSheet(isLandscape: Bool) {
        guard isSheetExpanded else {
            return
        }
        attachSheet(isLandscape: isLandscape)
        guard !sheetSlot.isLandscape, !isSheetOffsetPinned else {
            return
        }
        let target = detentConstant(expanded: isSheetDetentExpanded)
        if sheetTopConstraint?.constant != target {
            sheetTopConstraint?.constant = target
        }
    }

    // MARK: - Attach / detach

    private func attachSheet(isLandscape: Bool) {
        guard let content = sheetView,
              sheetSlot.isLandscape != isLandscape
              || content.superview == nil
        else {
            return
        }
        detachSheet()
        if isLandscape {
            attachLandscapeSheet(content)
        } else {
            attachPortraitSheet(content)
        }
        sheetSlot.isLandscape = isLandscape
        relatedCollectionView.isHidden = isLandscape
    }

    private func detachSheet() {
        NSLayoutConstraint.deactivate(sheetSlot.landscape)
        sheetSlot.landscape = []
        sheetTopConstraint = nil
        sheetView?.removeFromSuperview()
    }

    private func attachPortraitSheet(_ content: PlayerSheetView) {
        view.addSubview(content)
        let top = content.topAnchor.constraint(
            equalTo: view.topAnchor, constant: view.bounds.height
        )
        NSLayoutConstraint.activate([
            top,
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        sheetTopConstraint = top
        view.bringSubviewToFront(content)
    }

    private func attachLandscapeSheet(_ content: PlayerSheetView) {
        sidebarContainer.addSubview(content)
        let cp = content
        let sc = sidebarContainer
        // The top edge is a movable constraint here too, so the same drag
        // that dismisses the panel in portrait works in the sidebar: it
        // slides down and uncovers the related list.
        let top = cp.topAnchor.constraint(equalTo: sc.topAnchor)
        sheetSlot.landscape = [
            top,
            cp.leadingAnchor.constraint(equalTo: sc.leadingAnchor),
            cp.trailingAnchor.constraint(equalTo: sc.trailingAnchor),
            cp.heightAnchor.constraint(equalTo: sc.heightAnchor)
        ]
        NSLayoutConstraint.activate(sheetSlot.landscape)
        sheetTopConstraint = top
    }

    // MARK: - Detents

    /// Resting: top edge just below the player. Expanded: top of the safe
    /// area, i.e. full screen.
    private func detentConstant(expanded: Bool) -> CGFloat {
        guard !sheetSlot.isLandscape else {
            // The sidebar panel only rests at the top or leaves entirely.
            return 0
        }
        return expanded ? view.safeAreaInsets.top : playerContainer.frame.maxY
    }

    private func animateSheet(toExpandedDetent expanded: Bool) {
        isSheetDetentExpanded = expanded
        let target = detentConstant(expanded: expanded)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.3,
            options: .curveEaseOut
        ) {
            self.sheetTopConstraint?.constant = target
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Drag

    @objc
    func handleSheetPan(_ gesture: UIPanGestureRecognizer) {
        guard let constraint = sheetTopConstraint else {
            return
        }
        switch gesture.state {
        case .began:
            isSheetOffsetPinned = true
        case .changed:
            applySheetDrag(constraint, gesture: gesture)
        case .ended, .cancelled, .failed:
            finishSheetDrag(velocity: gesture.velocity(in: view).y)
        default:
            break
        }
    }

    /// Deltas since the last call, not since `.began` — the gesture's own
    /// translation is zeroed after each read, so no separate drag-start
    /// constant needs to be tracked on the controller.
    private func applySheetDrag(
        _ constraint: NSLayoutConstraint,
        gesture: UIPanGestureRecognizer
    ) {
        let delta = gesture.translation(in: view).y
        gesture.setTranslation(.zero, in: view)
        let minConstant = detentConstant(expanded: true)
        let maxConstant = sheetOffscreenConstant
        constraint.constant = min(max(constraint.constant + delta, minConstant), maxConstant)
        view.layoutIfNeeded()
    }

    private func finishSheetDrag(velocity: CGFloat) {
        isSheetOffsetPinned = false
        guard let constraint = sheetTopConstraint else {
            return
        }
        let resting = detentConstant(expanded: false)
        let expanded = detentConstant(expanded: true)
        let pastDismissLine = constraint.constant > resting + Self.dismissSlop
        if pastDismissLine || velocity > Self.flingVelocity {
            collapseSheet()
            return
        }
        if velocity < -Self.flingVelocity {
            animateSheet(toExpandedDetent: true)
            return
        }
        let midpoint = (resting + expanded) / 2
        animateSheet(toExpandedDetent: constraint.constant < midpoint)
    }
}
