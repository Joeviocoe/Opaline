import UIKit

/// The download flow, shared by the watch screen's action bar and the "..."
/// menu on every video row: ask for a quality, start the job, report how it
/// went. One entry point so both places behave identically.
enum DownloadMenu {
    /// Rows to append to a video's action menu. Which one appears depends on
    /// whether the video is already saved.
    static func items(
        for video: Video,
        from presenter: UIViewController,
        anchor: UIView
    ) -> [PlayerMenuItem] {
        // A live stream has no end to save.
        guard !video.isLive else {
            return []
        }
        switch DownloadStatus.of(video.id) {
        case .ready:
            return [deleteItem(video.id, from: presenter)]
        case .queued, .running:
            return [cancelItem(video.id)]
        case .failed:
            return [
                downloadItem(
                    video,
                    from: presenter,
                    anchor: anchor,
                    titleKey: "downloads.retry"
                ),
                deleteItem(video.id, from: presenter)
            ]
        case .none:
            return [
                downloadItem(
                    video,
                    from: presenter,
                    anchor: anchor,
                    titleKey: "player.action.download"
                )
            ]
        }
    }

    private static func downloadItem(
        _ video: Video,
        from presenter: UIViewController,
        anchor: UIView,
        titleKey: String
    ) -> PlayerMenuItem {
        PlayerMenuItem(title: titleKey.localized, iconName: "icon_download") {
            promptQuality(for: video, from: presenter, anchor: anchor)
        }
    }

    private static func deleteItem(
        _ videoId: String,
        from presenter: UIViewController
    ) -> PlayerMenuItem {
        PlayerMenuItem(
            title: "downloads.delete".localized,
            isDestructive: true,
            iconName: "icon_minus_circle"
        ) {
            remove(videoId, from: presenter)
        }
    }

    /// Cancels whichever job this video is — running or still waiting.
    private static func cancelItem(_ videoId: String) -> PlayerMenuItem {
        PlayerMenuItem(
            title: "downloads.cancel".localized,
            isDestructive: true,
            iconName: "icon_minus_circle"
        ) {
            VideoDownloader.shared.cancel(videoId)
        }
    }

    static func remove(_ videoId: String, from presenter: UIViewController) {
        DownloadStore.remove(videoId)
        ToastView.show("downloads.deleted".localized, in: presenter.view)
    }

    /// Asks the server what this video can be saved at, then offers it.
    static func promptQuality(
        for video: Video,
        from presenter: UIViewController,
        anchor: UIView?
    ) {
        VideoDownloader.shared.options(for: video.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let options) where !options.isEmpty:
                    present(options, for: video, from: presenter, anchor: anchor)
                case .success:
                    toast("downloads.error.noOptions", in: presenter, isError: true)
                case .failure(let error):
                    AppLog.downloads("options failed: \(error)")
                    toast("downloads.error.failed", in: presenter, isError: true)
                }
            }
        }
    }

    private static func present(
        _ options: [DownloadOption],
        for video: Video,
        from presenter: UIViewController,
        anchor: UIView?
    ) {
        let items = options.map { option in
            PlayerMenuItem(
                title: "\(option.label) · \(sizeText(option.bytes))",
                iconName: "icon_download"
            ) {
                start(video, option: option, from: presenter)
            }
        }
        let host = VideoActionMenu.menuHost(presenter)
        PlayerMenuOverlay.show(
            in: host,
            title: "downloads.quality.title".localized,
            items: items,
            style: .themed,
            from: anchor.map { $0.convert($0.bounds, to: host) }
        )
    }

    static func start(
        _ video: Video,
        option: DownloadOption,
        from presenter: UIViewController
    ) {
        // The menu may have been opened before another tap queued this very
        // video; without this the caller gets a "started" toast and a "busy"
        // toast on top of each other.
        guard !DownloadStatus.of(video.id).isActive else {
            toast("downloads.queued", in: presenter)
            return
        }
        VideoDownloader.shared.start(video: video, option: option) { result in
            switch result {
            case .success:
                toast("downloads.finished", in: presenter)
            case .failure(let error):
                AppLog.downloads("job failed: \(error)")
                toast("downloads.error.failed", in: presenter, isError: true)
            }
        }
        toast("downloads.started", in: presenter)
    }

    /// The presenter may well be gone by the time a job ends — a download
    /// outlives the screen it was started from.
    private static func toast(
        _ key: String,
        in presenter: UIViewController,
        isError: Bool = false
    ) {
        guard presenter.viewIfLoaded?.window != nil else {
            return
        }
        ToastView.show(key.localized, in: presenter.view, isError: isError)
    }

    static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
