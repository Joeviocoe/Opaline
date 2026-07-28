import UIKit

/// Window root: hosts the tab bar controller and, above it, the player panel.
///
/// The panel cannot be a child of `MainTabBarController` — a tab bar
/// controller's `children` *are* its `viewControllers`, so any extra child
/// shows up as a blank, iconless tab once the bar re-lays out (issue #30).
/// Parenting it here keeps the status-bar / home-indicator forwarding chain
/// while leaving the tab bar with exactly its three tabs.
final class RootContainerViewController: UIViewController {
    let mainTabBar: MainTabBarController

    // The player panel, when installed, is the last child — and the one that
    // owns the status bar and home indicator while it is on screen.
    override var childForStatusBarStyle: UIViewController? { children.last }
    override var childForStatusBarHidden: UIViewController? { children.last }
    override var childForHomeIndicatorAutoHidden: UIViewController? { children.last }

    override var shouldAutorotate: Bool {
        mainTabBar.shouldAutorotate
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        mainTabBar.supportedInterfaceOrientations
    }

    init(mainTabBar: MainTabBarController) {
        self.mainTabBar = mainTabBar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(mainTabBar)
        mainTabBar.view.frame = view.bounds
        mainTabBar.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mainTabBar.view)
        mainTabBar.didMove(toParent: self)
    }
}
