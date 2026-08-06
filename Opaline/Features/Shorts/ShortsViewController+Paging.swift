import UIKit

// MARK: - Collection data source & paging

extension ShortsViewController: UICollectionViewDataSource {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        videos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShortsCell.reuseIdentifier, for: indexPath
        )
        guard let shortsCell = cell as? ShortsCell else {
            return cell
        }
        let video = videos[indexPath.item]
        shortsCell.configure(with: video)
        shortsCell.onAction = { [weak self] action, video in
            self?.handle(action, for: video)
        }
        let page = watchPage(for: video.id)
        shortsCell.configure(
            likeCount: page?.likeCount,
            commentCount: nil,
            likeStatus: likeStatus(for: video.id),
            avatarURL: page?.channelInfo?.avatarURL ?? video.channelAvatarURL
        )
        return shortsCell
    }
}

extension ShortsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        playerView.setPaused(!playerView.isPaused)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settleOnCurrentPage()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settleOnCurrentPage()
    }

    private func settleOnCurrentPage() {
        let index = indexForCurrentOffset()
        guard index != attachedIndex else {
            return
        }
        attachPlayer(to: index)
    }
}
