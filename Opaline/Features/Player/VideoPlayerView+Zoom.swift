import AVFoundation
import ObjectiveC
import UIKit

// MARK: - Fullscreen Pinch Zoom

extension VideoPlayerView {
    /// Hard ceiling for pinch zoom, relative to aspect-fit (200%).
    static let maxPinchZoom: CGFloat = 2

    /// Auto zoom-to-fill setting (Playback settings menu).
    static var autoZoomToFill: Bool {
        UserDefaults.standard.bool(
            forKey: UserDefaultsKeys.Player.autoZoomToFill
        )
    }

    /// Scale at which the video covers the whole view (no bars).
    /// 1 when the video already fills or its size is not yet known.
    var fillZoom: CGFloat {
        // Derived from the item's size, not `playerLayer.videoRect`: the
        // layer only catches up with a bounds change on the next layout
        // pass, and fullscreen entry asks for the fill scale before that.
        let video = playerLayer.player?.currentItem?.presentationSize
            ?? .zero
        guard video.width > 0, video.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return 1
        }
        let fit = min(
            bounds.width / video.width,
            bounds.height / video.height
        )
        let fill = max(
            bounds.width / video.width,
            bounds.height / video.height
        )
        return fit > 0 ? fill / fit : 1
    }

    /// Animate to the fill scale when the setting is on and the user
    /// hasn't pinched manually. Called on fullscreen entry and whenever
    /// the layer (re)becomes ready — covers autoplay video changes.
    func applyAutoZoomIfNeeded() {
        guard Self.autoZoomToFill, isFullscreen,
              videoZoom <= 1.01 || zoomIsAuto else {
            return
        }
        let fill = fillZoom
        let target = fill > 1.01 ? fill : 1
        guard abs(target - videoZoom) > 0.01 else {
            return
        }
        setZoom(target, animated: true)
        zoomIsAuto = target > 1
    }

    func observeReadyForDisplay() {
        readyObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.new]
        ) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else {
                return
            }
            #if LEGACY_IOS9
            LegacyPlaybackTimeline.mark("FIRST FRAME on screen")
            #endif
            DispatchQueue.main.async {
                self?.applyAutoZoomIfNeeded()
            }
        }
    }

    func handleFullscreenPinch(
        _ gesture: UIPinchGestureRecognizer
    ) {
        switch gesture.state {
        case .began:
            pinchStartZoom = videoZoom
            zoomIsAuto = false
        case .changed:
            let limit = max(Self.maxPinchZoom, fillZoom)
            let proposed = pinchStartZoom * gesture.scale
            setZoom(
                min(max(proposed, 1), limit),
                animated: false
            )
            showHUD(text: zoomHUDText())
        case .ended, .cancelled, .failed:
            finishPinch(endScale: gesture.scale)
        default:
            break
        }
    }

    private func finishPinch(endScale: CGFloat) {
        // Pinch-in while already at 100% keeps the old
        // exit-fullscreen shortcut.
        if pinchStartZoom <= 1.01, endScale < 0.8 {
            hideHUD(after: 0)
            delegate?.videoPlayerViewDidTapFullscreen(self)
            return
        }
        let snapped = snappedZoom(videoZoom)
        if snapped != videoZoom {
            setZoom(snapped, animated: true)
        }
        showHUD(text: zoomHUDText())
        hideHUD(after: 0.8)
    }

    /// Snap near-fit back to 100% and near-fill onto the exact
    /// fill scale so bars disappear completely.
    private func snappedZoom(_ zoom: CGFloat) -> CGFloat {
        let fill = fillZoom
        if fill > 1.01, abs(zoom - fill) < fill * 0.08 {
            return fill
        }
        if zoom < 1.05 {
            return 1
        }
        return zoom
    }

    func setZoom(_ zoom: CGFloat, animated: Bool) {
        videoZoom = zoom
        let scale = CGAffineTransform(
            scaleX: zoom,
            y: zoom
        )
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeInEaseOut)
            )
            playerLayer.setAffineTransform(scale)
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.setAffineTransform(scale)
        CATransaction.commit()
    }

    // MARK: - Zoom HUD

    private func zoomHUDText() -> String {
        let fill = fillZoom
        if fill > 1.01, abs(videoZoom - fill) < 0.01 {
            return "  Fill  "
        }
        let percent = Int((videoZoom * 100).rounded())
        return "  \(percent)%  "
    }
}

// MARK: - Shared HUD (zoom % and seek offset)

extension VideoPlayerView {
    func showHUD(text: String) {
        if hudLabel.superview == nil {
            setupHUDLabel()
        }
        hudWorkItem?.cancel()
        hudLabel.text = text
        hudLabel.alpha = 1
    }

    func hideHUD(after delay: TimeInterval) {
        hudWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.2) {
                self?.hudLabel.alpha = 0
                // Only fade it if it was ever shown -- peeking rather than
                // going through the lazy-create getter, so a plain zoom/
                // volume/mute/speed HUD (which never uses the position
                // label) does not pay to instantiate one it will never show.
                self?.existingHudPositionLabel?.alpha = 0
            }
        }
        hudWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }

    private func setupHUDLabel() {
        addSubview(hudLabel)
        NSLayoutConstraint.activate([
            hudLabel.centerXAnchor.constraint(
                equalTo: centerXAnchor
            ),
            hudLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: 24
            ),
            hudLabel.heightAnchor.constraint(
                equalToConstant: 28
            )
        ])
    }
}

// MARK: - Second HUD label, for the seek/scrub position

private var hudPositionLabelKey: UInt8 = 0

extension VideoPlayerView {
    /// Trailing-anchored, same row as `hudLabel`, for "current / total" next
    /// to a centered offset. A computed property backed by an associated
    /// object rather than a stored one on the class -- VideoPlayerView.swift
    /// is already near the linter's file-length limit, and every other
    /// screen-scoped piece of new UI in this branch uses the same idiom
    /// (ListFocusInstaller, KeyboardFocusCoordinator).
    var hudPositionLabel: UILabel {
        if let existing = existingHudPositionLabel {
            return existing
        }
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        // Natural alignment, like `hudLabel` — deliberately *not* `.right`,
        // which is what the trailing anchor invites. Both HUDs pad their box
        // by wrapping the text in spaces, and text layout drops trailing
        // whitespace when it aligns a line: right-aligned, the two spaces on
        // the end stopped counting and the text sat flush against the right
        // edge of its own background with all the padding piled up on the
        // left. Left/natural just draws from the start, so both pads render.
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -12
            ),
            label.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: 24
            ),
            label.heightAnchor.constraint(equalToConstant: 28)
        ])
        objc_setAssociatedObject(
            self,
            &hudPositionLabelKey,
            label,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return label
    }

    var existingHudPositionLabel: UILabel? {
        objc_getAssociatedObject(self, &hudPositionLabelKey) as? UILabel
    }

    func showPositionHUD(text: String) {
        let label = hudPositionLabel
        label.text = text
        label.alpha = 1
    }
}
