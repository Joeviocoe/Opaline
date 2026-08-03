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

    private let logoView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ThemeManager.shared.background
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateAndComplete()
    }

    // MARK: - UI

    private func setupUI() {
        logoView.image = UIImage(named: "LaunchLogo")
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.alpha = 0
        view.addSubview(logoView)

        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logoView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.15),
            logoView.heightAnchor.constraint(equalTo: logoView.widthAnchor, multiplier: 0.7)
        ])
    }

    // MARK: - Animation

    private func animateAndComplete() {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.logoView.alpha = 1
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIView.animate(withDuration: 0.25) {
                    self.logoView.alpha = 0
                } completion: { _ in
                    self.onComplete?()
                }
            }
        }
    }
}
