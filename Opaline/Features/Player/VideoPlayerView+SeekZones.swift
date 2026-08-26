import UIKit

/// Double-tap zones, as in the official app: a quarter of the width on each
/// side seeks, and the half between them toggles playback. Splitting the
/// player 50/50 left the middle to one of the two seek directions, so a
/// double tap had nowhere to mean anything else (#107).
extension VideoPlayerView {
    enum SeekZone {
        case rewind, playPause, forward
    }

    private static let seekZoneTag = 7_301
    private static let seekZoneWidthRatio: CGFloat = 0.25

    func seekZone(atX xPosition: CGFloat) -> SeekZone {
        let edge = bounds.width * Self.seekZoneWidthRatio
        if xPosition < edge {
            return .rewind
        }
        if xPosition > bounds.width - edge {
            return .forward
        }
        return .playPause
    }

    /// A brief dim over the side that was tapped, rounded on its inner edge.
    /// The middle zone gets none: the play/pause icon already changes.
    func flashSeekZone(_ zone: SeekZone) {
        guard zone != .playPause else {
            return
        }
        viewWithTag(Self.seekZoneTag)?.removeFromSuperview()
        let width = bounds.width * Self.seekZoneWidthRatio
        let flash = UIView(frame: CGRect(
            x: zone == .rewind ? 0 : bounds.width - width,
            y: 0,
            width: width,
            height: bounds.height
        ))
        flash.tag = Self.seekZoneTag
        flash.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        flash.isUserInteractionEnabled = false
        flash.layer.cornerRadius = bounds.height / 2
        flash.layer.maskedCorners = zone == .rewind
            ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        insertSubview(flash, belowSubview: controlsView)
        UIView.animate(
            withDuration: 0.35,
            animations: { flash.alpha = 0 },
            completion: { _ in flash.removeFromSuperview() }
        )
    }
}
