import UIKit

/// Long-press / "..." action sheet for a video, shared by every list and
/// grid that shows one (Home, Search, Library, Channel, Subscriptions).
/// A single entry point keeps "Play next", "Save to playlist" etc. in one
/// place instead of duplicated per screen. Built on the same
/// `PlayerMenuOverlay` the watch screen uses rather than a system alert,
/// so it looks and behaves the same everywhere.
enum VideoActionMenu {
    /// The menu for a row of the playing queue. It leads with the way out of
    /// the queue, drops "Add to queue" — everything on that list is queued
    /// already — and drops "Play now" for what is playing right now.
    struct QueueContext {
        let isPlaying: Bool
        let remove: () -> Void
    }

    /// Everything the caller can vary, bundled: the two contexts a menu can
    /// be opened from are a playlist screen and the queue panel.
    private struct Options {
        let remove: (playlist: (id: String, title: String), onRemoved: (() -> Void)?)?
        let queue: QueueContext?
        /// Also used on its own by the feedback actions, which drop the
        /// video from whatever list it was opened from.
        let onRemoved: (() -> Void)?
        let outcome: FeedbackOutcome
    }

    static func present(
        video: Video,
        from presenter: UIViewController,
        anchor: UIView,
        removeFrom playlist: (id: String, title: String)? = nil,
        onRemoved: (() -> Void)? = nil,
        queue: QueueContext? = nil,
        feedbackOutcome: FeedbackOutcome = .tunedRecommendations
    ) {
        let remove = playlist.map { (playlist: $0, onRemoved: onRemoved) }
        let items = menuItems(
            video: video,
            from: presenter,
            anchor: anchor,
            options: Options(
                remove: remove,
                queue: queue,
                onRemoved: onRemoved,
                outcome: feedbackOutcome
            )
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
        options: Options
    ) -> [PlayerMenuItem] {
        var items = baseItems(
            video: video,
            from: presenter,
            anchor: anchor,
            queue: options.queue
        )
        if let remove = options.remove {
            items.append(removeItem(
                video,
                playlist: remove.playlist,
                from: presenter,
                onRemoved: remove.onRemoved
            ))
        }
        return items + feedbackItems(
            video: video,
            from: presenter,
            outcome: options.outcome,
            onRemoved: options.onRemoved
        )
    }

    private static func baseItems(
        video: Video,
        from presenter: UIViewController,
        anchor: UIView,
        queue: QueueContext?
    ) -> [PlayerMenuItem] {
        var items = leadingItems(
            video: video,
            from: presenter,
            queue: queue
        )
        // Only where the card carried one: plenty of TV tiles arrive without
        // a channel id, and a row that goes nowhere is worse than no row.
        if let channelId = video.channelId, !channelId.isEmpty {
            items.append(PlayerMenuItem(
                title: "video.menu.goToChannel".localized,
                iconName: "icon_person_fill"
            ) {
                VideoRouter.shared.openChannel(
                    id: channelId,
                    name: video.channelName,
                    from: presenter
                )
            })
        }
        // No "Watch later" row: "Save to playlist" right below it already
        // offers Watch Later, and the feedback actions need the space.
        return items
            + saveAndShareItems(video: video, from: presenter, anchor: anchor)
            + DownloadMenu.items(for: video, from: presenter, anchor: anchor)
    }

    /// The head of the menu, which is what a queue row changes.
    private static func leadingItems(
        video: Video,
        from presenter: UIViewController,
        queue: QueueContext?
    ) -> [PlayerMenuItem] {
        var items: [PlayerMenuItem] = []
        if queue?.isPlaying != true {
            items.append(PlayerMenuItem(
                title: "player.autoplay.playNow".localized,
                iconName: "icon_play_fill"
            ) {
                VideoRouter.shared.open(video: video, from: presenter)
            })
        }
        if let queue = queue, !queue.isPlaying {
            items.append(PlayerMenuItem(
                title: "video.menu.removeFromQueue".localized,
                iconName: "icon_minus_circle",
                handler: queue.remove
            ))
        }
        guard queue == nil else {
            return items
        }
        items.append(PlayerMenuItem(
            title: "video.menu.playNext".localized,
            iconName: "icon_text_append"
        ) {
            playNext(video, from: presenter)
        })
        return items
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
