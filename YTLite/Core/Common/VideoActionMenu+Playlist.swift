import UIKit

// MARK: - Playlist actions

/// Watch Later and the playlist picker both fetch the same
/// add-to-playlist option list and send back one of its ready-made
/// actions — see `InnertubeClient+PlaylistEdit.swift`. Mirrors
/// `WatchViewController+Save.swift` without reusing its view-controller
/// state, since this menu can be presented from anywhere.
extension VideoActionMenu {
    private static let watchLaterId = "WL"

    static func addToWatchLater(
        _ video: Video,
        from presenter: UIViewController,
        client: PlaylistService = ServiceContainer.playlists,
        engagement: EngagementService = ServiceContainer.engagement
    ) {
        fetchOptions(videoId: video.id, client: client) { options in
            guard let options else {
                showFailed(in: presenter.view)
                return
            }
            let existing = options.first { $0.id == watchLaterId }
            if existing?.isAdded == true {
                showSaved(title: existing?.title ?? "", in: presenter.view)
                return
            }
            let actions = existing?.addActions
                // ponytail: fallback if "WL" is absent from the response —
                // known shape, same as WatchViewController's own toggle.
                ?? [["action": "ACTION_ADD_VIDEO", "addedVideoId": video.id]]
            performEdit(
                playlistId: watchLaterId,
                actions: actions,
                engagement: engagement
            ) { success in
                if success {
                    showSaved(title: "video.menu.watchLaterName".localized, in: presenter.view)
                } else {
                    showFailed(in: presenter.view)
                }
            }
        }
    }

    static func presentPlaylistPicker(
        for video: Video,
        from presenter: UIViewController,
        anchor: UIView,
        client: PlaylistService = ServiceContainer.playlists,
        engagement: EngagementService = ServiceContainer.engagement
    ) {
        fetchOptions(videoId: video.id, client: client) { options in
            guard let options, !options.isEmpty else {
                showFailed(in: presenter.view)
                return
            }
            let items = options.map { option in
                PlayerMenuItem(
                    title: option.isAdded ? "\u{2713} \(option.title)" : option.title
                ) {
                    toggle(option, from: presenter, engagement: engagement)
                }
            }
            let host = menuHost(presenter)
            PlayerMenuOverlay.show(
                in: host,
                title: nil,
                items: items,
                style: .themed,
                from: anchor.convert(anchor.bounds, to: host)
            )
        }
    }

    static func removeFromPlaylist(
        _ video: Video,
        playlist: (id: String, title: String),
        from presenter: UIViewController,
        onRemoved: (() -> Void)?,
        client: PlaylistService = ServiceContainer.playlists,
        engagement: EngagementService = ServiceContainer.engagement
    ) {
        fetchOptions(videoId: video.id, client: client) { options in
            let actions = options?.first { $0.id == playlist.id }?.removeActions
                // ponytail: fallback if this playlist is absent from the
                // response — known shape, same as WatchViewController's own toggle.
                ?? [["action": "ACTION_REMOVE_VIDEO_BY_VIDEO_ID", "removedVideoId": video.id]]
            performEdit(
                playlistId: playlist.id,
                actions: actions,
                engagement: engagement
            ) { success in
                guard success else {
                    showFailed(in: presenter.view)
                    return
                }
                ToastView.show(
                    "player.action.removedFrom".localized(with: playlist.title),
                    in: presenter.view
                )
                onRemoved?()
            }
        }
    }

    private static func toggle(
        _ option: PlaylistAddOption,
        from presenter: UIViewController,
        engagement: EngagementService
    ) {
        let removing = option.isAdded
        let actions = removing ? option.removeActions : option.addActions
        guard !actions.isEmpty else {
            showFailed(in: presenter.view)
            return
        }
        performEdit(
            playlistId: option.id,
            actions: actions,
            engagement: engagement
        ) { success in
            guard success else {
                showFailed(in: presenter.view)
                return
            }
            let key = removing ? "player.action.removedFrom" : "player.action.savedTo"
            ToastView.show(key.localized(with: option.title), in: presenter.view)
        }
    }

    private static func fetchOptions(
        videoId: String,
        client: PlaylistService,
        completion: @escaping ([PlaylistAddOption]?) -> Void
    ) {
        client.fetchAddToPlaylistOptions(videoId: videoId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let options):
                    completion(options)
                case .failure(let error):
                    AppLog.player("VideoActionMenu: fetch options failed \(error)")
                    completion(nil)
                }
            }
        }
    }

    private static func performEdit(
        playlistId: String,
        actions: [[String: Any]],
        engagement: EngagementService,
        completion: @escaping (Bool) -> Void
    ) {
        engagement.editPlaylist(playlistId: playlistId, actions: actions) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(true)
                case .failure(let error):
                    AppLog.player("VideoActionMenu: edit playlist failed \(error)")
                    completion(false)
                }
            }
        }
    }

    private static func showSaved(title: String, in view: UIView) {
        ToastView.show("player.action.savedTo".localized(with: title), in: view)
    }

    private static func showFailed(in view: UIView) {
        ToastView.show("player.action.saveFailed".localized, in: view)
    }
}
