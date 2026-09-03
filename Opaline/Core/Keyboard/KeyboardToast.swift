import UIKit

/// A brief confirmation for keyboard actions that change something off-screen.
///
/// The player has `showHUD` for this, but it lives on `VideoPlayerView` and is
/// useless on a list: pressing `q` on a row queues a video with no visible
/// effect anywhere, which reads exactly like the key not working. There was no
/// app-wide toast to reuse, so this is the smallest one that fits the house
/// style — themed, non-interactive, and gone in a moment.
enum KeyboardToast {
    private static let tag = 7_411
    private static let visibleFor: TimeInterval = 1.4

    /// Inverted against the theme, so it reads as an overlay rather than as
    /// part of the screen underneath.
    private static func makeLabel(_ text: String) -> PaddedLabel {
        let theme = ThemeManager.shared
        let label = PaddedLabel()
        label.tag = tag
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = theme.isDark ? .black : .white
        label.backgroundColor = theme.isDark ? .white : .black
        label.textAlignment = .center
        label.numberOfLines = 1
        label.isUserInteractionEnabled = false
        label.layer.cornerRadius = 18
        label.layer.masksToBounds = true
        label.alpha = 0
        return label
    }

    /// Shown over the window rather than the list, so it survives the list
    /// reloading underneath it.
    static func show(_ text: String, over view: UIView?) {
        guard let host = view?.window else {
            return
        }
        host.viewWithTag(tag)?.removeFromSuperview()

        let label = makeLabel(text)
        let size = label.intrinsicContentSize
        label.frame = CGRect(
            x: (host.bounds.width - size.width) / 2,
            y: host.bounds.height - size.height - 120,
            width: size.width,
            height: size.height
        )
        host.addSubview(label)

        UIView.animate(withDuration: 0.18, animations: { label.alpha = 1 })
        UIView.animate(
            withDuration: 0.3,
            delay: visibleFor,
            options: [],
            animations: { label.alpha = 0 },
            completion: { _ in label.removeFromSuperview() }
        )
    }
}

/// A label with room around its text — `UILabel` has no inset of its own, and a
/// pill with the text jammed against the corner radius looks broken.
private final class PaddedLabel: UILabel {
    private static let inset = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(
            width: base.width + Self.inset.left + Self.inset.right,
            height: base.height + Self.inset.top + Self.inset.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: Self.inset))
    }
}
