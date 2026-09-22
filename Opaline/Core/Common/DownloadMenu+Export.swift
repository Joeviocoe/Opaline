import UIKit

/// Taking a downloaded video back out of the app: the muxed MP4 goes to the
/// system share sheet, where "Save to Files" and every other app that accepts
/// a video come from iOS. Nothing else in the download folder leaves with it.
extension DownloadMenu {
    static func exportItem(
        _ video: Video,
        from presenter: UIViewController,
        anchor: UIView
    ) -> PlayerMenuItem {
        PlayerMenuItem(
            title: "downloads.export".localized,
            iconName: "icon_share"
        ) {
            export(video, from: presenter, anchor: anchor)
        }
    }

    /// Hands the muxed file to the system share sheet: "Save to Files" is an
    /// extension iOS brings itself, so there is nothing of ours between the
    /// video and Files. Only the video goes — the captions, comments and
    /// metadata sitting beside it mean nothing outside the app.
    static func export(
        _ video: Video,
        from presenter: UIViewController,
        anchor: UIView
    ) {
        guard let file = exportFile(for: video) else {
            return
        }
        let activity = UIActivityViewController(
            activityItems: [file], applicationActivities: nil
        )
        VideoActionMenu.anchorPopover(activity, to: anchor)
        presenter.present(activity, animated: true)
    }

    /// Every download is `video.mp4` on disk, which says nothing in Files.
    /// The link is named after the video instead, and costs neither the space
    /// nor the wait a copy of a gigabyte would: both paths live in the same
    /// container. It lands in the temporary directory, which iOS empties.
    static func exportFile(for video: Video) -> URL? {
        let manager = FileManager.default
        let source = DownloadStore.videoFile(for: video.id)
        guard manager.fileExists(atPath: source.path) else {
            AppLog.downloads("export: nothing on disk for \(video.id)")
            return nil
        }
        let destination = manager.temporaryDirectory
            .appendingPathComponent(exportName(for: video))
        try? manager.removeItem(at: destination)
        if (try? manager.linkItem(at: source, to: destination)) == nil,
           (try? manager.copyItem(at: source, to: destination)) == nil {
            AppLog.downloads("export: could not stage \(video.id)")
            return nil
        }
        return destination
    }

    /// Whatever a file name cannot hold, and short enough that Files has
    /// something left to show after the extension.
    static func exportName(for video: Video) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
        let name = video.title
            .components(separatedBy: banned)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? video.id : String(name.prefix(80))) + ".mp4"
    }
}
