import UIKit

/// Small circular badge overlaid on a channel avatar's top-right
/// edge when the channel has unwatched recent uploads. The border
/// matches the screen background so the dot reads as floating over
/// the clipped avatar circle.
final class NewContentDotView: UIView {
    static let size: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = NewContentDotView.size / 2
        layer.borderWidth = 2
        isHidden = true
        applyTheme()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(
                equalToConstant: NewContentDotView.size
            ),
            heightAnchor.constraint(
                equalToConstant: NewContentDotView.size
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.newContentDot
        layer.borderColor = theme.background.cgColor
    }

    /// Pins the dot to the avatar's top-right edge in the shared
    /// superview of both views.
    func constrainToTopRight(of avatar: UIView) {
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(
                equalTo: avatar.trailingAnchor,
                constant: -5
            ),
            centerYAnchor.constraint(
                equalTo: avatar.topAnchor,
                constant: 5
            )
        ])
    }
}
