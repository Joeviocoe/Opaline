import UIKit

// MARK: - UICollectionViewDataSource

extension WatchViewController: UICollectionViewDataSource {
    private func configureChannelNavigation(
        for cell: VideoCell,
        video: Video
    ) {
        cell.onChannelTap = { [weak self] in
            guard let self,
                  let channelId = video.channelId
            else {
                return
            }
            navigationController?.pushViewController(
                channelViewControllerFactory(
                    channelId,
                    video.channelName
                ),
                animated: true
            )
        }
        cell.onMenuTap = { [weak self] anchor in
            guard let self else {
                return
            }
            VideoActionMenu.present(video: video, from: self, anchor: anchor)
        }
    }

    func numberOfSections(
        in collectionView: UICollectionView
    )
        -> Int {
        isPlaylistMode ? 2 : 1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    )
        -> Int {
        if isPlaylistMode {
            return section == 0
                ? max(0, queue.videos.count - 1)
                : visibleRelatedVideos.count
        }
        return visibleRelatedVideos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    )
        -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: VideoCell.reuseId,
            for: indexPath
        ) as? VideoCell else {
            return UICollectionViewCell()
        }
        let video: Video? = if isPlaylistMode {
            indexPath.section == 0
                ? queue.videos[safe: indexPath.item + 1]
                : visibleRelatedVideos[safe: indexPath.item]
        } else {
            visibleRelatedVideos[safe: indexPath.item]
        }
        guard let video else {
            return cell
        }
        let isLandscape =
            view.bounds.width > view.bounds.height
        cell.forceGridLayout = !isLandscape
        cell.configure(with: video)
        configureChannelNavigation(for: cell, video: video)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    )
        -> UICollectionReusableView {
        guard kind == UICollectionView
            .elementKindSectionHeader
        else {
            return UICollectionReusableView()
        }
        let header = collectionView
            .dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier:
                PlaylistSectionHeaderView.reuseIdentifier,
                for: indexPath
            ) as? PlaylistSectionHeaderView
            ?? PlaylistSectionHeaderView()
        let title: String = if isPlaylistMode, indexPath.section == 0 {
            queue.playlistTitle ?? "player.related.mix".localized
        } else {
            "player.related.title".localized
        }
        header.configure(
            title: title,
            color: ThemeManager.shared.primaryText
        )
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension WatchViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath
    )
        -> Bool {
        !isOuterScrollViewDragging
            && !scrollView.isDecelerating
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let video: Video? = if isPlaylistMode {
            indexPath.section == 0
                ? queue.videos[safe: indexPath.item + 1]
                : visibleRelatedVideos[safe: indexPath.item]
        } else {
            visibleRelatedVideos[safe: indexPath.item]
        }
        guard let video else {
            return
        }
        navigateTo(video)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension WatchViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    )
        -> CGSize {
        CGSize(
            width: collectionView.bounds.width,
            height: WatchViewController.relatedHeaderHeight
        )
    }
}

// MARK: - UIScrollViewDelegate

extension WatchViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        isOuterScrollViewDragging = true
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        if !decelerate {
            isOuterScrollViewDragging = false
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        isOuterScrollViewDragging = false
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        guard scrollView === self.scrollView else {
            return
        }
        let threshold: CGFloat = 400
        let offset = scrollView.contentOffset.y
            + scrollView.bounds.height
        let contentHeight = scrollView.contentSize.height
        guard contentHeight > 0,
              offset >= contentHeight - threshold
        else {
            return
        }
        expandRelatedIfNeeded()
    }
}

// MARK: - PlaybackContext

extension WatchViewController: PlaybackContext {
    func updateStatusLabel(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            playerStatusLabel.text = text
            playerStatusLabel.isHidden = false
            playerSpinner.startAnimating()
        }
    }

    func setCaptionTracks(_ tracks: [SubtitleTrack]) {
        captionTracks = tracks
        videoPlayerView?.setCaptionTracks(
            tracks,
            activeLanguage: activeSubtitleLanguage
        )
        videoPlayerView?.onCCTapped = { [weak self] in
            self?.showSubtitlePicker()
        }
    }
}

// MARK: - Safe Collection Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
