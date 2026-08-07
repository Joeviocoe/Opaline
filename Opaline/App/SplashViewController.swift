import UIKit

final class SplashViewController: UIViewController {
    /// Without this the bar draws in `.default`, which on iOS 12 always means
    /// dark text — unreadable over the dark theme's background this screen is
    /// painted with. From iOS 13 `.default` follows the window's interface
    /// style, which is why the splash only ever looked wrong on 12.
    override var preferredStatusBarStyle: UIStatusBarStyle {
        ThemeManager.shared.statusBarStyle
    }

    var onComplete: (() -> Void)?

    /// The triangle's share of the screen width, matching the launch storyboard
    /// so the handover from it is seamless. Only the background changes after
    /// that — the mark holds this size throughout, in both themes.
    private let logoWidth: CGFloat = 0.15

    private let logoView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Starts on the storyboard's black rather than the theme background, so
        // the two screens line up pixel-for-pixel before anything animates; the
        // light theme then crossfades to its own background below.
        view.backgroundColor = .black
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateAndComplete()
    }

    // MARK: - UI

    private func setupUI() {
        // Drawn as-is, never as a template: the mark carries the opal gradient
        // itself, which is the whole point of it — a tint would flatten the brand
        // back into the plain triangle it used to be on the dark theme.
        logoView.image = UIImage(named: "SplashMark")
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        // Faded in rather than matched to the storyboard's own mark: iOS 12 lays
        // the storyboard's image view out but never draws its image, so there the
        // handover is from bare black and a hard cut would pop. On iOS 13+ the
        // storyboard does draw it, and this fades in over an identical mark.
        logoView.alpha = 0
        view.addSubview(logoView)

        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logoView.widthAnchor.constraint(
                equalTo: view.widthAnchor, multiplier: logoWidth
            ),
            logoView.heightAnchor.constraint(equalTo: logoView.widthAnchor, multiplier: 1.017)
        ])
    }

    // MARK: - Animation

    private func animateAndComplete() {
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
            // Lands on the theme background the next screen is painted with, so
            // the root swap isn't a flash, and the mark sits on white or black
            // exactly as the icon does.
            self.view.backgroundColor = ThemeManager.shared.background
            self.logoView.alpha = 1
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                UIView.animate(withDuration: 0.25) {
                    self.logoView.alpha = 0
                } completion: { _ in
                    self.onComplete?()
                }
            }
        }
    }
}
