import UIKit

/// Sizing for a view used as a `UIBarButtonItem.customView`.
///
/// iOS 11 lays bar items out with Auto Layout, so the view's own size
/// constraints are what the bar reads. iOS 9 and 10 position custom views
/// by frame — and a custom view that has opted out of the autoresizing mask
/// is placed by the constraint engine instead, with nothing pinning it, so
/// it lands at the bar's origin: the avatar and bell sat on top of each
/// other at the top-left, up against the status bar. On those versions the
/// frame set in `init` is the whole story.
enum BarCustomView {
    static func size(_ view: UIView, side: CGFloat) {
        if #available(iOS 11, *) {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: side).isActive = true
            view.heightAnchor.constraint(equalToConstant: side).isActive = true
        } else {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.frame = CGRect(x: 0, y: 0, width: side, height: side)
        }
    }
}
