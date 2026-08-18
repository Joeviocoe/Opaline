import UIKit

final class VideoRouter {
    static let shared = VideoRouter()

    var watchViewControllerFactory: ((Video) -> WatchViewController)?
    /// Shorts open in their own full-screen vertical feed, not the watch screen.
    var shortsViewControllerFactory: ((Video, ShortsEntry) -> UIViewController)?
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

    private var keyWindowMainTabBar: MainTabBarController? {
        var root = (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return (root as? RootContainerViewController)?.mainTabBar
            ?? root as? MainTabBarController
    }

    private init() {}

    /// - Parameter shorts: how the shorts feed continues past `video` —
    ///   see `ShortsEntry`.
    func open(
        video: Video,
        from presenter: UIViewController,
        shorts: ShortsEntry = .pool([])
    ) {
        if video.isShort,
           ShortsPlayerMode.selected == .vertical,
           let makeShorts = shortsViewControllerFactory {
            // The outermost one: Library's segments sit in an embedded
            // navigation controller whose view stops below the status bar,
            // and a full-screen feed pushed there leaves that strip showing
            // the screen underneath.
            presenter.visibleNavigationController?.pushViewController(
                makeShorts(video, shorts), animated: true
            )
            return
        }
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

    /// Opens a video known only by id — e.g. a `ytlite://` deep link or a
    /// tapped youtube.com link. `seconds` is the link's own timecode
    /// (`?t=87`), which outranks stored watch progress. Presents on the
    /// currently selected tab of `MainTabBarController`; a no-op if the main
    /// UI isn't up yet.
    func openVideoId(_ videoId: String, startAt seconds: Double? = nil) {
        if let seconds {
            WatchProgressStore.shared.setLinkStart(
                seconds: seconds, forVideoId: videoId
            )
        }
        guard let tabBar = keyWindowMainTabBar,
              let presenter = tabBar.selectedViewController
        else {
            return
        }
        open(video: Video(id: videoId), from: presenter)
    }

    func minimize() {
        panel?.collapse(animated: true)
    }

    /// Pushes a channel screen onto the tab underneath the player and
    /// collapses the player to the mini bar — matching the official app,
    /// which never lets a pushed screen cover the expanded player.
    func openChannel(id: String, name: String) {
        guard let factory = channelViewControllerFactory,
              let tabNav = panel?.owner?.selectedViewController as? UINavigationController
        else {
            return
        }
        tabNav.pushViewController(factory(id, name), animated: true)
        minimize()
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
