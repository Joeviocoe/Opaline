import UIKit

// MARK: - Overlay actions

extension ShortsViewController {
    func handle(_ action: ShortsActionRail.Action, for video: Video) {
        switch action {
        case .channel:
            openChannel(for: video)
        case .like:
            toggleLike(.like, for: video)
        case .dislike:
            toggleLike(.dislike, for: video)
        case .comments:
            openComments(for: video)
        case .share:
            share(video)
        }
    }

    /// Tapping the active state clears it, as on the watch screen. The tint
    /// flips immediately — the request lands too late to feel like a reply
    /// to the tap.
    private func toggleLike(_ status: LikeStatus, for video: Video) {
        let wasActive = likeStatus(for: video.id) == status
        let next: LikeStatus = wasActive ? .indifferent : status
        setLikeStatus(next, for: video.id)
        if next == .like {
            Feedback.success()
        }
        refreshOverlay(for: video.id)
        let completion: (Result<Void, Error>) -> Void = { result in
            if case .failure(let error) = result {
                AppLog.player("shorts like failed: \(error)")
            }
        }
        switch next {
        case .indifferent:
            engagementService.removeLike(videoId: video.id, completion: completion)
        case .like:
            engagementService.sendLike(videoId: video.id, completion: completion)
        case .dislike:
            engagementService.sendDislike(videoId: video.id, completion: completion)
        }
    }

    private func openComments(for video: Video) {
        let sheet = ShortsCommentsViewController(
            videoId: video.id, watchService: watchService
        )
        if #available(iOS 13.0, *) {
            sheet.modalPresentationStyle = .pageSheet
        } else {
            sheet.modalPresentationStyle = .formSheet
        }
        present(sheet, animated: true)
    }

    private func share(_ video: Video) {
        guard let url = URL(string: "https://youtu.be/\(video.id)") else {
            return
        }
        let sheet = UIActivityViewController(
            activityItems: [url], applicationActivities: nil
        )
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0
            )
        }
        present(sheet, animated: true)
    }
}
