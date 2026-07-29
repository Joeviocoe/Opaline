import UIKit

final class VideoRouter {
    static let shared = VideoRouter()

    var watchViewControllerFactory: ((Video) -> WatchViewController)?
    /// Lets Core screens push a channel without importing Features.
    var channelViewControllerFactory: ((String, String) -> UIViewController)?
    private var panel: PlayerPanelViewController?

    /// The video currently loaded in the mini/full player, if any — lets
    /// `VideoActionMenu` seed an empty queue with the right "now playing"
    /// item instead of guessing.
    var currentVideo: Video? {
        guard let watchVC = panel?.watchVC else {
            return nil
        }
        return watchVC.watchPage?.video ?? watchVC.initialVideo
    }

    private init() {}

    func open(video: Video, from presenter: UIViewController) {
        if let panel {
            panel.watchVC.loadVideo(video)
            panel.expand(animated: true)
            return
        }
        guard let factory = watchViewControllerFactory else {
            assertionFailure("VideoRouter not configured")
            return
        }
        let watchVC = factory(video)
        let newPanel = PlayerPanelViewController(watchVC: watchVC)
        newPanel.onClose = { [weak self] in
            self?.panel = nil
        }
        panel = newPanel
        guard let tabBar = findTabBarController(from: presenter) else {
            self.panel = nil
            return
        }
        tabBar.installPlayerPanel(newPanel)
    }

    func minimize() {
        panel?.collapse(animated: true)
    }

    /// Brings the full player back — used when PiP asks the app to restore
    /// its own playback UI, which AVKit expects to be on screen.
    func expandPanel() {
        panel?.expand(animated: false)
    }

    func clearCurrentWatch() {
        panel?.close()
    }

    private func findTabBarController(from vc: UIViewController) -> MainTabBarController? {
        var root = vc.view.window?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return (root as? RootContainerViewController)?.mainTabBar
            ?? root as? MainTabBarController
            ?? vc.tabBarController as? MainTabBarController
            ?? vc.navigationController?.tabBarController as? MainTabBarController
    }
}
