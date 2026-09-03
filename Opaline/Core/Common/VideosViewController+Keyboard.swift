import UIKit

/// One conformance, two screens: `HomeViewController` and
/// `ChannelViewController` both subclass this. It is a grid, so it takes the
/// horizontal arrows as well — and the geometric search is what copes with the
/// three different cell shapes this feed renders (grid cells, the taller shorts
/// grid, and full-width rail rows) without any of them being special-cased.
extension VideosViewController: ListFocusHost {
    var listFocusScrollView: UIScrollView? { collectionView }
    var listFocusAxis: ListFocusController.Axis { .grid }

    func listFocusVideo(at indexPath: IndexPath) -> Video? {
        guard indexPath.section < sections.count,
              indexPath.item < sections[indexPath.section].videos.count
        else {
            return nil
        }
        return video(at: indexPath)
    }
}
