import UIKit

/// Long-press / "..." action sheet for a video, shared by every list and
/// grid that shows one (Home, Search, Library, Channel, Subscriptions).
/// A single entry point keeps "Play next", "Save to playlist" etc. in one
/// place instead of duplicated per screen. Built on the same
/// `PlayerMenuOverlay` the watch screen uses rather than a system alert,
/// so it looks and behaves the same everywhere.
enum VideoActionMenu {
    static func present(
        video: Video,
        from presenter: UIViewController,
        anchor: UIView,
        removeFrom playlist: (id: String, title: String)? = nil,
        onRemoved: (() -> Void)? = nil
    ) {
        let remove = playlist.map { (playlist: $0, onRemoved: onRemoved) }
        let items = menuItems(
            video: video,
            from: presenter,
            anchor: anchor,
            remove: remove
        )
        let host = menuHost(presenter)
        PlayerMenuOverlay.show(
            in: host,
            title: nil,
            items: items,
            style: .themed,
            from: anchor.convert(anchor.bounds, to: host)
        )
    }

    /// The window, not the presenter's view: on the watch screen the related
    /// list sits in a view stacked above the controller's own, so an overlay
    /// added there renders underneath it and never receives the tap that
    /// dismisses it — every further tap then stacked another dimming layer.
    static func menuHost(_ presenter: UIViewController) -> UIView {
        presenter.view.window ?? presenter.view
    }

    private static func menuItems(
        video: Video,
        from presenter: UIViewController,
        anchor: UIView,
        remove: (playlist: (id: String, title: String), onRemoved: (() -> Void)?)?
    ) -> [PlayerMenuItem] {
        var items = baseItems(video: video, from: presenter, anchor: anchor)
        if let remove {
            items.append(removeItem(
                video,
                playlist: remove.playlist,
                from: presenter,
                onRemoved: remove.onRemoved
            ))
        }
        return items
    }

    private static func baseItems(
        video: Video,
        from presenter: UIViewController,
        anchor: UIView
    ) -> [PlayerMenuItem] {
        [
            PlayerMenuItem(
                title: "player.autoplay.playNow".localized,
                iconName: "icon_play_fill"
            ) {
                VideoRouter.shared.open(video: video, from: presenter)
            },
            PlayerMenuItem(
                title: "video.menu.playNext".localized,
                iconName: "icon_text_append"
            ) {
                playNext(video, from: presenter)
            },
            PlayerMenuItem(
                title: "video.menu.watchLater".localized,
                iconName: "icon_clock"
            ) {
                addToWatchLater(video, from: presenter)
            }
        ]
            + saveAndShareItems(video: video, from: presenter, anchor: anchor)
            + DownloadMenu.items(for: video, from: presenter, anchor: anchor)
    }

    private static func saveAndShareItems(
        video: Video,
        from presenter: UIViewController,
        anchor: UIView
    ) -> [PlayerMenuItem] {
        [
            PlayerMenuItem(
                title: "player.action.saveTo".localized,
                iconName: "icon_bookmark"
            ) {
                presentPlaylistPicker(for: video, from: presenter, anchor: anchor)
            },
            PlayerMenuItem(
                title: "player.action.share".localized,
                iconName: "icon_share"
            ) {
                shareVideo(video, from: presenter, anchor: anchor)
            }
        ]
    }

    private static func removeItem(
        _ video: Video,
        playlist: (id: String, title: String),
        from presenter: UIViewController,
        onRemoved: (() -> Void)?
    ) -> PlayerMenuItem {
        PlayerMenuItem(
            title: "video.menu.removeFrom".localized(with: playlist.title),
            isDestructive: true,
            iconName: "icon_minus_circle"
        ) {
            removeFromPlaylist(
                video,
                playlist: playlist,
                from: presenter,
                onRemoved: onRemoved
            )
        }
    }

    /// iPad presents `UIActivityViewController` as a popover and crashes
    /// without an anchor — `PlayerMenuOverlay` needs no such anchor, so
    /// this is only used for the system share sheet.
    private static func anchorPopover(_ presented: UIViewController, to anchor: UIView) {
        guard let popover = presented.popoverPresentationController else {
            return
        }
        popover.sourceView = anchor
        popover.sourceRect = anchor.bounds
    }

    private static func playNext(_ video: Video, from presenter: UIViewController) {
        guard let current = VideoRouter.shared.currentVideo else {
            VideoRouter.shared.open(video: video, from: presenter)
            return
        }
        PlaybackQueue.shared.playNext(video, current: current)
        ToastView.show("video.menu.queued".localized, in: presenter.view)
    }

    private static func shareVideo(
        _ video: Video,
        from presenter: UIViewController,
        anchor: UIView
    ) {
        guard let url = URL(string: "https://youtu.be/\(video.id)") else {
            return
        }
        let activity = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        anchorPopover(activity, to: anchor)
        presenter.present(activity, animated: true)
    }
}
