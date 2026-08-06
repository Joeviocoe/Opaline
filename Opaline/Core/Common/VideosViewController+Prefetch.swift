import UIKit

extension VideosViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        guard !isLoadingInitial else {
            return
        }
        for indexPath in indexPaths {
            guard indexPath.section < sections.count,
                  indexPath.item < sections[indexPath.section].videos.count
            else {
                continue
            }
            let video = video(at: indexPath)
            if let url = URL(string: video.thumbnailURL) {
                ThumbnailImageView.prefetch(url: url)
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            guard indexPath.section < sections.count,
                  indexPath.item < sections[indexPath.section].videos.count
            else {
                continue
            }
            let video = video(at: indexPath)
            if let url = URL(string: video.thumbnailURL) {
                ThumbnailImageView.cancelPrefetch(url: url)
            }
        }
    }
}
