import UIKit

protocol ScrollableToTop: AnyObject {
    func scrollToTop()
}

class MainTabBarController: UITabBarController {
    private let dependencies: AppDependencies
    private weak var playerPanel: PlayerPanelViewController?
    private var miniPlayerBar: MiniPlayerBar?
    private var miniPlayerBarBottomConstraint: NSLayoutConstraint?

    // The player panel is parented to `RootContainerViewController`, which
    // forwards these to it directly — see the note there.
    override var childForStatusBarHidden: UIViewController? {
        selectedViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        selectedViewController
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        selectedViewController
    }

    override var shouldAutorotate: Bool {
        if UIDevice.current.userInterfaceIdiom != .pad {
            return false
        }
        return selectedViewController?.shouldAutorotate ?? super.shouldAutorotate
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom != .pad {
            return .portrait
        }
        return selectedViewController?.supportedInterfaceOrientations
            ?? super.supportedInterfaceOrientations
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
        ToolbarManager.shared.searchViewControllerFactory = { [dependencies] in
            dependencies.makeSearchViewController()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        viewControllers = buildTabs()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        applyTheme()
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *),
           traitCollection.hasDifferentColorAppearance(
               comparedTo: previousTraitCollection
           ) {
            ThemeManager.shared.refreshAutoTheme()
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.tabBar.setNeedsLayout()
            },
            completion: { [weak self] _ in
                self?.tabBar.setNeedsLayout()
                self?.tabBar.layoutIfNeeded()
            }
        )
    }

    private func buildTabs() -> [UIViewController] {
        [makeHomeTab(), makeSubscriptionsTab(), makeLibraryTab()]
    }

    private func makeHomeTab() -> UIViewController {
        let home = RotatingNavigationController(
            rootViewController: HomeViewController(
                service: dependencies.feedService,
                channelViewControllerFactory:
                    dependencies.makeChannelViewController
            )
        )
        home.tabBarItem = UITabBarItem(
            title: "home.title".localized,
            image: TabBarIcons.home(),
            tag: 0
        )
        return home
    }

    private func makeSubscriptionsTab() -> UIViewController {
        let subs = RotatingNavigationController(
            rootViewController:
                dependencies.makeSubscriptionsViewController()
        )
        subs.tabBarItem = UITabBarItem(
            title: "subscriptions.title".localized,
            image: TabBarIcons.subscriptions(),
            tag: 1
        )
        return subs
    }

    private func makeLibraryTab() -> UIViewController {
        let library = RotatingNavigationController(
            rootViewController: LibraryViewController(
                dependencies: dependencies
            )
        )
        library.tabBarItem = UITabBarItem(
            title: "library.title".localized,
            image: TabBarIcons.library(),
            tag: 2
        )
        return library
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        tabBar.barStyle = theme.barStyle
        tabBar.tintColor = theme.isDark ? .white : theme.accent
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = theme.surface
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        }
        miniPlayerBar?.applyTheme()
    }

    func installPlayerPanel(_ panel: PlayerPanelViewController) {
        if let existing = playerPanel {
            removePlayerPanel(existing)
        }
        // Parent the panel to the root container, never to self: a tab bar
        // controller's children are its tabs (issue #30). UIKit requires a
        // child's view to sit in its parent's hierarchy, so the panel view goes
        // into the container's view — which is above ours, tab bar included.
        let host: UIViewController = parent ?? self
        host.addChild(panel)
        panel.view.frame = host.view.bounds
        panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(panel.view)
        panel.didMove(toParent: host)
        panel.owner = self
        playerPanel = panel

        miniPlayerBar?.removeFromSuperview()
        let bar = MiniPlayerBar()
        view.addSubview(bar)
        // Use a proportional width (1/3 of the parent) so the bar stays correctly
        // sized after device rotation without needing to recreate the constraint.
        let bottomConstraint = bar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -12
        )
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1.0 / 3.0),
            bottomConstraint
        ])
        bar.isHidden = true
        bar.alpha = 0
        miniPlayerBar = bar
        miniPlayerBarBottomConstraint = bottomConstraint

        panel.miniBar = bar
        panel.view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        panel.expand(animated: true)
    }

    func removePlayerPanel(_ panel: PlayerPanelViewController) {
        if playerPanel === panel {
            playerPanel = nil
        }
        miniPlayerBar?.removeFromSuperview()
        miniPlayerBar = nil
        miniPlayerBarBottomConstraint = nil
        panel.willMove(toParent: nil)
        panel.view.removeFromSuperview()
        panel.removeFromParent()
        // Defer the tab-bar re-layout to the next run-loop cycle so UIKit
        // finishes all internal hierarchy cleanup before we force a layout.
        // Without this, item positions can be stale after a
        // landscape → fullscreen → portrait → close sequence.
        DispatchQueue.main.async { [weak self] in
            self?.tabBar.setNeedsLayout()
            self?.tabBar.layoutIfNeeded()
        }
    }
}

// MARK: - UITabBarControllerDelegate

extension MainTabBarController: UITabBarControllerDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        guard viewController === selectedViewController,
              let nav = viewController as? UINavigationController
        else {
            return true
        }
        if nav.viewControllers.count > 1 {
            nav.popToRootViewController(animated: true)
        } else if let scrollable = nav.topViewController as? ScrollableToTop {
            scrollable.scrollToTop()
        }
        return true
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        Feedback.select()
        Feedback.pop(selectedTabIcon())
    }

    /// The icon inside the tab button, not the button: the bar owns its
    /// buttons' frames and resets them, which fights an animated transform.
    private func selectedTabIcon() -> UIView? {
        let buttons = tabBar.subviews
            .filter { $0 is UIControl }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard selectedIndex < buttons.count else {
            return nil
        }
        return buttons[selectedIndex].subviews.first { $0 is UIImageView }
    }
}
