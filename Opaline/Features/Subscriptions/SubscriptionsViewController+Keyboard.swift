import UIKit

/// A single-column list, so it deliberately does not claim the horizontal
/// arrows — they fall through the chain to the player, which is what lets a
/// video keep its seek keys while the subscriptions feed is on screen.
extension SubscriptionsViewController: ListFocusHost {
    /// Rows are a mix of videos and shelves, so only the video ones answer.
    func listFocusVideo(at indexPath: IndexPath) -> Video? {
        guard indexPath.row < rows.count else {
            return nil
        }
        if case .video(let video) = rows[indexPath.row] {
            return video
        }
        return nil
    }
}
