import UIKit

// MARK: - Shorts tab

extension MainTabBarController {
    static let shortsTabTag = 3

    var wantsShortsTab: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.Feed.showShorts)
    }

    /// Adds or removes the tab in place rather than rebuilding every tab: the
    /// others keep their view controllers, and so their loaded feeds and
    /// scroll positions. Selection is restored by identity because assigning
    /// `viewControllers` resets it to the first tab.
    @objc
    func handleShowShortsTabChange() {
        let existing = viewControllers?.first {
            $0.tabBarItem.tag == Self.shortsTabTag
        }
        guard wantsShortsTab == (existing == nil) else {
            return
        }
        var tabs = viewControllers ?? []
        let selected = selectedViewController
        if let existing {
            tabs.removeAll { $0 === existing }
        } else {
            tabs.insert(makeShortsTab(), at: min(2, tabs.count))
        }
        viewControllers = tabs
        if let selected, let index = tabs.firstIndex(where: { $0 === selected }) {
            selectedIndex = index
        }
    }

    func makeShortsTab() -> UIViewController {
        let shorts = RotatingNavigationController(
            rootViewController: dependencies.makeShortsViewController(
                seedVideo: nil, entry: .cold
            )
        )
        shorts.tabBarItem = UITabBarItem(
            title: "shorts.shelf.title".localized,
            image: TabBarIcons.shorts(),
            tag: 3
        )
        return shorts
    }
}
