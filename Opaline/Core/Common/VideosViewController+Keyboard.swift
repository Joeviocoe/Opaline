import UIKit

/// One conformance, two screens: `HomeViewController` and
/// `ChannelViewController` both subclass this. It is a grid, so it takes the
/// horizontal arrows as well — and the geometric search is what copes with the
/// three different cell shapes this feed renders (grid cells, the taller shorts
/// grid, and full-width rail rows) without any of them being special-cased.
///
/// No `listFocusVideo(at:)` override here — `ListFocusHost`'s default derives
/// it from whichever cell (`VideoCell` or `ShortThumbnailCell`) is actually on
/// screen, so `q` works on both cell shapes this feed uses without this file
/// knowing which one is at a given index path.
extension VideosViewController: ListFocusHost {
    var listFocusScrollView: UIScrollView? { collectionView }
    var listFocusAxis: ListFocusController.Axis { .grid }
}
