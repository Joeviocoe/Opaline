import UIKit

// MARK: - Playing queue

extension WatchViewController {
    /// The queue as a menu list. The mix/playlist section in the related feed
    /// shows the same videos, but it sits below the description and comments —
    /// this reaches it from the player itself, where the queue is playing.
    func showQueue() {
        let current = watchPage?.video.id ?? initialVideo.id
        let items = queue.videos.map { video -> PlayerMenuItem in
            let isCurrent = video.id == current
            return PlayerMenuItem(
                title: isCurrent ? "✓ \(video.title)" : video.title
            ) { [weak self] in
                guard !isCurrent else {
                    return
                }
                self?.navigateTo(video)
            }
        }
        presentPlayerMenu(
            title: queue.playlistTitle ?? "player.menu.queue".localized,
            items: items
        )
    }
}
