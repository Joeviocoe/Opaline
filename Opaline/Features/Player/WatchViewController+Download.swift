import UIKit

// MARK: - Download

extension WatchViewController {
    private var downloadVideo: Video {
        watchPage?.video ?? initialVideo
    }

    /// Accent once the video is here, plain while it is on its way, yellow
    /// when it stopped and wants a decision — the same three colours the
    /// badge on a video card uses.
    private static func tint(for status: DownloadStatus) -> UIColor {
        switch status {
        case .ready:
            return ThemeManager.shared.accent
        case .failed:
            return .systemYellow
        default:
            return ThemeManager.shared.primaryText
        }
    }

    private static func runningCaption(_ downloader: VideoDownloader) -> String {
        downloader.isMuxing
            ? "downloads.muxing".localized
            : "\(Int(downloader.progress * 100))%"
    }
    @objc
    func downloadTapped() {
        let video = downloadVideo
        let downloader = VideoDownloader.shared
        if downloader.activeVideoId == video.id {
            presentDownloadProgressMenu()
        } else if DownloadStore.isDownloaded(video.id) {
            presentPlayerMenu(
                title: "player.action.download".localized,
                items: DownloadMenu.items(
                    for: video, from: self, anchor: downloadButton
                )
            )
        } else if downloader.isQueued(video.id) {
            presentPlayerMenu(
                title: "downloads.queued".localized,
                items: DownloadMenu.items(
                    for: video, from: self, anchor: downloadButton
                )
            )
        } else {
            DownloadMenu.promptQuality(
                for: video, from: self, anchor: downloadButton
            )
        }
    }

    /// Accent while a download is running or already on disk, matching how
    /// the save button marks a video that sits in a playlist.
    @objc
    func updateDownloadButton() {
        let video = downloadVideo
        let downloader = VideoDownloader.shared
        let running = downloader.activeVideoId == video.id
        let status = DownloadStatus.of(video.id)
        downloadButton.tintColor = Self.tint(for: status)
        downloadStatusLabel.text = running
            ? Self.runningCaption(downloader)
            : "player.action.download".localized
        setDownloadPulse(active: status.isActive)
    }

    /// Same signal as the badge on a video card, so a download reads the same
    /// wherever it is looked at.
    private func setDownloadPulse(active: Bool) {
        guard active else {
            downloadButton.layer.removeAnimation(forKey: "pulse")
            downloadButton.alpha = 1
            return
        }
        guard downloadButton.layer.animation(forKey: "pulse") == nil else {
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        downloadButton.layer.add(pulse, forKey: "pulse")
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
}
