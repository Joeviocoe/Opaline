import UIKit

// MARK: - Autoplay

extension WatchViewController {
    func showAutoplayOverlay(for video: Video) {
        AppLog.player(
            "autoplay overlay: showing for \(video.id),"
                + " fullscreen=\(videoPlayerView?.isFullscreen == true)"
        )
        autoplayOverlay?.removeFromSuperview()
        let overlay = makeAutoplayOverlay(for: video)
        if let pv = videoPlayerView, pv.isFullscreen {
            overlay.translatesAutoresizingMaskIntoConstraints = true
            overlay.frame = pv.bounds
            overlay.autoresizingMask = [
                .flexibleWidth, .flexibleHeight
            ]
            pv.addSubview(overlay)
        } else {
            overlay
                .translatesAutoresizingMaskIntoConstraints
                = false
            playerContainer.addSubview(overlay)
            applyEdgeConstraints(
                overlay,
                to: playerContainer
            )
        }
        autoplayOverlay = overlay
        UIView.animate(withDuration: 0.25) {
            overlay.alpha = 1
        }
        overlay.startCountdown()
    }

    private func makeAutoplayOverlay(
        for video: Video
    ) -> AutoplayOverlayView {
        let overlay = AutoplayOverlayView(
            nextVideo: video,
            countdownSecs: 5
        )
        overlay.alpha = 0
        overlay.onPlay = { [weak self] in
            self?.dismissAutoplayOverlay()
            self?.navigateTo(video)
        }
        overlay.onCancel = { [weak self] in
            self?.dismissAutoplayOverlay()
        }
        return overlay
    }

    func applyEdgeConstraints(
        _ child: UIView,
        to parent: UIView
    ) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(
                equalTo: parent.topAnchor
            ),
            child.leadingAnchor.constraint(
                equalTo: parent.leadingAnchor
            ),
            child.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor
            ),
            child.bottomAnchor.constraint(
                equalTo: parent.bottomAnchor
            )
        ])
    }

    /// Control Center / AirPods "next": queue entry first, else the top
    /// suggestion — always instant, never the countdown overlay.
    func playNextFromRemote() {
        dismissAutoplayOverlay()
        if let next = queue.nextVideo {
            AppLog.player("remote next: queue \(next.id)")
            navigateTo(next)
            return
        }
        guard let suggestion = watchPage?.nextVideo else {
            AppLog.player("remote next: nothing to play")
            return
        }
        AppLog.player("remote next: suggestion \(suggestion.id)")
        navigateTo(suggestion)
    }

    /// Control Center / AirPods "previous": the session's own back stack
    /// (`videoHistory`, same as the nav-bar back button). On a mix the
    /// reloaded watch page re-syncs the queue to the earlier position.
    /// With no history left, restart the video — the standard fallback.
    func previousFromRemote() {
        dismissAutoplayOverlay()
        guard videoHistory.isEmpty else {
            AppLog.player("remote previous: history back")
            goBack()
            return
        }
        AppLog.player("remote previous: restart")
        videoPlayerView?.player?.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        videoPlayerView?.player?.play()
    }

    func dismissAutoplayOverlay() {
        guard let overlay = autoplayOverlay else {
            return
        }
        autoplayOverlay = nil
        UIView.animate(
            withDuration: 0.2,
            animations: { overlay.alpha = 0 },
            completion: { _ in
                overlay.removeFromSuperview()
            }
        )
    }
}
