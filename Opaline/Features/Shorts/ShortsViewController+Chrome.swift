import UIKit

// MARK: - Screen chrome: back button, overlay and progress bar

extension ShortsViewController {
    /// With the navigation bar hidden the screen needs its own way back —
    /// except on the Shorts tab, where the feed is the navigation root and
    /// there is nothing behind it.
    func setupBackButton() {
        guard navigationController?.viewControllers.first !== self else {
            return
        }
        let back = NavChevronButton(
            kind: .back, target: self, action: #selector(backTapped)
        )
        back.tintColor = .white
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8
            ),
            back.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8
            )
        ])
    }

    /// Shorts play edge to edge over black, and a light tab bar under them is
    /// a bright band the official app does not have. Restoring goes through
    /// the theme notification — the tab bar controller owns its colours.
    func setTabBarDark(_ dark: Bool) {
        guard let tabBar = tabBarController?.tabBar else {
            return
        }
        if #available(iOS 13.0, *) {
            tabBar.overrideUserInterfaceStyle = dark ? .dark : .unspecified
        }
        guard dark else {
            NotificationCenter.default.post(
                name: ThemeManager.didChangeNotification, object: nil
            )
            return
        }
        tabBar.barStyle = .black
        tabBar.tintColor = .white
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    @objc
    func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    /// The overlay lives here, not in the cell: it has to sit in the screen's
    /// safe area, which is what keeps it clear of the tab bar and the
    /// display's rounded corners.
    func setupOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onAction = { [weak self] action, video in
            self?.handle(action, for: video)
        }
        view.addSubview(overlay)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.backgroundColor = ThemeManager.shared.accent
        view.addSubview(progressBar)
        let width = progressBar.widthAnchor.constraint(equalToConstant: 0)
        progressWidth = width
        NSLayoutConstraint.activate([
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 3),
            width
        ])
        playerView.onProgress = { [weak self] fraction in
            self?.applyProgress(fraction)
        }
    }

    private func applyProgress(_ fraction: Double) {
        progressWidth?.constant = view.bounds.width
            * CGFloat(min(max(fraction, 0), 1))
        // First non-zero position of the run: the picture is up.
        if fraction > 0, !didLogFirstFrame {
            didLogFirstFrame = true
            logShortsTiming("first frame")
        }
    }
}
