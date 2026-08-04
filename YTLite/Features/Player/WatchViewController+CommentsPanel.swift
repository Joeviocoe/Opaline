import UIKit

/// Presentation for the expanded comments panel (`CommentsPanelView`).
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

    // MARK: - Present / dismiss

    func presentCommentsPanel() {
        let isLandscape = view.bounds.width > view.bounds.height
        attachCommentsPanel(isLandscape: isLandscape)
        commentsPanel.isHidden = false
        guard !isLandscape else {
            return
        }
        commentsPanelTopConstraint?.constant = view.bounds.height
        view.layoutIfNeeded()
        animateCommentsPanel(toExpandedDetent: false)
    }

    func dismissCommentsPanel() {
        guard !commentsPanelSlot.isLandscape else {
            commentsPanel.isHidden = true
            detachCommentsPanel()
            relatedCollectionView.isHidden = false
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: .curveEaseIn,
            animations: {
                self.commentsPanelTopConstraint?.constant = self.view.bounds.height
                self.view.layoutIfNeeded()
            },
            completion: { [weak self] _ in
                guard let self, !self.isCommentsExpanded else {
                    return
                }
                self.commentsPanel.isHidden = true
                self.detachCommentsPanel()
            }
        )
    }

    /// Called on every layout pass (including mid-rotation) so the panel
    /// never gets stranded in the wrong parent or at a stale offset.
    func layoutCommentsPanel(isLandscape: Bool) {
        guard isCommentsExpanded else {
            return
        }
        attachCommentsPanel(isLandscape: isLandscape)
        guard !commentsPanelSlot.isLandscape, !isDraggingCommentsPanel else {
            return
        }
        let target = detentConstant(expanded: isCommentsPanelDetentExpanded)
        if commentsPanelTopConstraint?.constant != target {
            commentsPanelTopConstraint?.constant = target
        }
    }

    // MARK: - Attach / detach

    private func attachCommentsPanel(isLandscape: Bool) {
        guard commentsPanelSlot.isLandscape != isLandscape
            || commentsPanel.superview == nil
        else {
            return
        }
        detachCommentsPanel()
        if isLandscape {
            attachLandscapeCommentsPanel()
        } else {
            attachPortraitCommentsPanel()
        }
        commentsPanelSlot.isLandscape = isLandscape
        relatedCollectionView.isHidden = isLandscape
    }

    private func detachCommentsPanel() {
        NSLayoutConstraint.deactivate(commentsPanelSlot.landscape)
        commentsPanelSlot.landscape = []
        commentsPanelTopConstraint = nil
        commentsPanel.removeFromSuperview()
    }

    private func attachPortraitCommentsPanel() {
        view.addSubview(commentsPanel)
        let top = commentsPanel.topAnchor.constraint(
            equalTo: view.topAnchor, constant: view.bounds.height
        )
        NSLayoutConstraint.activate([
            top,
            commentsPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentsPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        commentsPanelTopConstraint = top
        view.bringSubviewToFront(commentsPanel)
    }

    private func attachLandscapeCommentsPanel() {
        sidebarContainer.addSubview(commentsPanel)
        let cp = commentsPanel
        let sc = sidebarContainer
        commentsPanelSlot.landscape = [
            cp.topAnchor.constraint(equalTo: sc.topAnchor),
            cp.leadingAnchor.constraint(equalTo: sc.leadingAnchor),
            cp.trailingAnchor.constraint(equalTo: sc.trailingAnchor),
            cp.bottomAnchor.constraint(equalTo: sc.bottomAnchor)
        ]
        NSLayoutConstraint.activate(commentsPanelSlot.landscape)
    }

    // MARK: - Detents

    /// Resting: top edge just below the player. Expanded: top of the safe
    /// area, i.e. full screen.
    private func detentConstant(expanded: Bool) -> CGFloat {
        expanded ? view.safeAreaInsets.top : playerContainer.frame.maxY
    }

    private func animateCommentsPanel(toExpandedDetent expanded: Bool) {
        isCommentsPanelDetentExpanded = expanded
        let target = detentConstant(expanded: expanded)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.3,
            options: .curveEaseOut
        ) {
            self.commentsPanelTopConstraint?.constant = target
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Drag

    @objc
    func handleCommentsPanelPan(_ gesture: UIPanGestureRecognizer) {
        guard !commentsPanelSlot.isLandscape,
              let constraint = commentsPanelTopConstraint
        else {
            return
        }
        switch gesture.state {
        case .began:
            isDraggingCommentsPanel = true
        case .changed:
            applyCommentsPanelDrag(constraint, gesture: gesture)
        case .ended, .cancelled, .failed:
            finishCommentsPanelDrag(velocity: gesture.velocity(in: view).y)
        default:
            break
        }
    }

    /// Deltas since the last call, not since `.began` — the gesture's own
    /// translation is zeroed after each read, so no separate drag-start
    /// constant needs to be tracked on the controller.
    private func applyCommentsPanelDrag(
        _ constraint: NSLayoutConstraint,
        gesture: UIPanGestureRecognizer
    ) {
        let delta = gesture.translation(in: view).y
        gesture.setTranslation(.zero, in: view)
        let minConstant = detentConstant(expanded: true)
        let maxConstant = view.bounds.height
        constraint.constant = min(max(constraint.constant + delta, minConstant), maxConstant)
        view.layoutIfNeeded()
    }

    private func finishCommentsPanelDrag(velocity: CGFloat) {
        isDraggingCommentsPanel = false
        guard let constraint = commentsPanelTopConstraint else {
            return
        }
        let resting = detentConstant(expanded: false)
        let expanded = detentConstant(expanded: true)
        let pastDismissLine = constraint.constant > resting + Self.dismissSlop
        if pastDismissLine || velocity > Self.flingVelocity {
            collapseComments()
            return
        }
        if velocity < -Self.flingVelocity {
            animateCommentsPanel(toExpandedDetent: true)
            return
        }
        let midpoint = (resting + expanded) / 2
        animateCommentsPanel(toExpandedDetent: constraint.constant < midpoint)
    }
}
