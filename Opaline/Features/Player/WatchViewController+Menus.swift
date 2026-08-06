import UIKit

// MARK: - Player menus

extension WatchViewController {
    /// All player menus use the same in-view overlay so the UI is identical
    /// inline and in fullscreen. A presented alert could not work there
    /// anyway: in fullscreen the player view sits directly in the window,
    /// above (and on iPhone rotated relative to) anything this controller
    /// presents.
    func presentPlayerMenu(title: String, items: [PlayerMenuItem]) {
        if isPlayerFullscreen, let playerView = videoPlayerView {
            PlayerMenuOverlay.show(
                in: playerView,
                title: title,
                items: items,
                style: .overVideo
            )
        } else {
            PlayerMenuOverlay.show(
                in: navigationController?.view ?? view,
                title: title,
                items: items,
                style: .themed
            )
        }
    }
}
