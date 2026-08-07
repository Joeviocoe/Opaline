import UIKit

// MARK: - Shorts tab

extension MainTabBarController {
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
