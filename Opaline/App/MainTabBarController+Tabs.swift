import UIKit

// MARK: - Tab construction

extension MainTabBarController {
    func buildTabs() -> [UIViewController] {
        var tabs = [makeHomeTab(), makeSubscriptionsTab()]
        // Only for users who want shorts at all — the same setting that
        // hides them from every feed.
        if wantsShortsTab {
            tabs.append(makeShortsTab())
        }
        tabs.append(makeLibraryTab())
        return tabs
    }

    func makeHomeTab() -> UIViewController {
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
            tag: DefaultTab.home.tabTag
        )
        return home
    }

    func makeSubscriptionsTab() -> UIViewController {
        let subs = RotatingNavigationController(
            rootViewController:
                dependencies.makeSubscriptionsViewController()
        )
        subs.tabBarItem = UITabBarItem(
            title: "subscriptions.title".localized,
            image: TabBarIcons.subscriptions(),
            tag: DefaultTab.subscriptions.tabTag
        )
        return subs
    }

    func makeLibraryTab() -> UIViewController {
        let library = RotatingNavigationController(
            rootViewController: LibraryViewController(
                dependencies: dependencies
            )
        )
        library.tabBarItem = UITabBarItem(
            title: "library.title".localized,
            image: TabBarIcons.library(),
            tag: DefaultTab.library.tabTag
        )
        return library
    }
}
