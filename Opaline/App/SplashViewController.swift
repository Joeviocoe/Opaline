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

    private let backgroundView = UIImageView()
    private let logoView = UIImageView()

    /// Dark mode keeps the storyboard's plain black — a gradient this bright is
    /// exactly what the dark theme (and the auto schedule's night hours) exists
    /// to avoid.
    private var showsGradient: Bool { !ThemeManager.shared.isDark }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Starts on the storyboard's black rather than the theme background, so
        // the two screens line up pixel-for-pixel before anything animates.
        view.backgroundColor = .black
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateAndComplete()
    }

    // MARK: - UI

    private func setupUI() {
        backgroundView.image = UIImage(named: "LaunchBackground")
        // The artwork is a soft blur with no recognisable shapes, so stretching
        // it to any aspect ratio is invisible — and unlike aspect-fill it never
        // crops. Hidden rather than absent so the animation stays branchless.
        backgroundView.contentMode = .scaleToFill
        backgroundView.isHidden = !showsGradient
        backgroundView.alpha = 0
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)

        // Template + tint, so the one white-triangle asset also works on the light
        // theme's near-white background. The asset itself stays non-template: the launch
        // storyboard draws it too, and there it would pick up the default tint.
        logoView.image = UIImage(named: "SplashMark")?.withRenderingMode(.alwaysTemplate)
        // On the gradient the triangle stays white, as it is in the icon.
        logoView.tintColor = showsGradient ? .white : ThemeManager.shared.primaryText
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        // Faded in rather than matched to the storyboard's own mark: iOS 12 lays
        // the storyboard's image view out but never draws its image, so there the
        // handover is from bare black and a hard cut would pop. On iOS 13+ the
        // storyboard does draw it, and this fades in over an identical mark.
        logoView.alpha = 0
        view.addSubview(logoView)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

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
            self.backgroundView.alpha = self.showsGradient ? 1 : 0
            self.logoView.alpha = 1
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                UIView.animate(withDuration: 0.25) {
                    self.logoView.alpha = 0
                    self.backgroundView.alpha = 0
                    // Lands on the theme background the next screen is painted
                    // with, so the root swap isn't a flash of black.
                    self.view.backgroundColor = ThemeManager.shared.background
                } completion: { _ in
                    self.onComplete?()
                }
            }
        }
    }
}
