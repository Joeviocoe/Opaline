import UIKit

// MARK: - Download

extension WatchViewController {
    private var downloadVideoId: String {
        watchPage?.video.id ?? initialVideo.id
    }

    private static func runningCaption(_ downloader: VideoDownloader) -> String {
        downloader.isMuxing
            ? "downloads.muxing".localized
            : "\(Int(downloader.progress * 100))%"
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    @objc
    func downloadTapped() {
        let videoId = downloadVideoId
        if VideoDownloader.shared.activeVideoId == videoId {
            presentDownloadProgressMenu()
        } else if DownloadStore.isDownloaded(videoId) {
            presentDownloadedMenu(videoId: videoId)
        } else {
            presentQualityPrompt(videoId: videoId)
        }
    }

    /// Accent while a download is running or already on disk, matching how
    /// the save button marks a video that sits in a playlist.
    @objc
    func updateDownloadButton() {
        let videoId = downloadVideoId
        let downloader = VideoDownloader.shared
        let running = downloader.activeVideoId == videoId
        let marked = running || DownloadStore.isDownloaded(videoId)
        downloadButton.tintColor = marked
            ? ThemeManager.shared.accent
            : ThemeManager.shared.primaryText
        downloadStatusLabel.text = running
            ? Self.runningCaption(downloader)
            : "player.action.download".localized
    }

    // MARK: - Menus

    private func presentQualityPrompt(videoId: String) {
        downloadButton.isEnabled = false
        VideoDownloader.shared.options(for: videoId) { [weak self] result in
            DispatchQueue.main.async {
                self?.downloadButton.isEnabled = true
                switch result {
                case .success(let options) where !options.isEmpty:
                    self?.presentQualityMenu(options, videoId: videoId)
                case .success:
                    self?.showDownloadToast("downloads.error.noOptions", isError: true)
                case .failure(let error):
                    AppLog.downloads("options failed: \(error)")
                    self?.showDownloadToast("downloads.error.failed", isError: true)
                }
            }
        }
    }

    private func presentQualityMenu(
        _ options: [DownloadOption],
        videoId: String
    ) {
        let items = options.map { option in
            PlayerMenuItem(
                title: "\(option.label) · \(Self.sizeText(option.bytes))",
                iconName: "icon_download"
            ) { [weak self] in
                self?.startDownload(videoId: videoId, option: option)
            }
        }
        presentPlayerMenu(title: "downloads.quality.title".localized, items: items)
    }

    private func presentDownloadProgressMenu() {
        let downloader = VideoDownloader.shared
        let title = downloader.isMuxing
            ? "downloads.muxing".localized
            : "downloads.progress".localized(
                with: "\(Int(downloader.progress * 100))"
            )
        let items = [
            PlayerMenuItem(
                title: "downloads.cancel".localized,
                isDestructive: true,
                iconName: "icon_minus_circle"
            ) { [weak self] in
                VideoDownloader.shared.cancel()
                self?.updateDownloadButton()
            }
        ]
        presentPlayerMenu(title: title, items: items)
    }

    private func presentDownloadedMenu(videoId: String) {
        let items = [
            PlayerMenuItem(
                title: "downloads.delete".localized,
                isDestructive: true,
                iconName: "icon_minus_circle"
            ) { [weak self] in
                DownloadStore.remove(videoId)
                self?.updateDownloadButton()
                self?.showDownloadToast("downloads.deleted")
            }
        ]
        presentPlayerMenu(
            title: "player.action.download".localized, items: items
        )
    }

    // MARK: - Job

    private func startDownload(videoId: String, option: DownloadOption) {
        VideoDownloader.shared.start(
            videoId: videoId,
            option: option
        ) { [weak self] result in
            self?.updateDownloadButton()
            switch result {
            case .success:
                self?.showDownloadToast("downloads.finished")
            case .failure(let error):
                self?.showDownloadToast("downloads.error.failed", isError: true)
                AppLog.downloads("job failed: \(error)")
            }
        }
        updateDownloadButton()
        showDownloadToast("downloads.started")
    }

    private func showDownloadToast(_ key: String, isError: Bool = false) {
        ToastView.show(key.localized, in: view, isError: isError)
    }
}
