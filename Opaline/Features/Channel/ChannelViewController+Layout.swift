import UIKit

extension ChannelViewController {
    func playlistFeedPage(
        from playlists: [Playlist],
        continuation: String? = nil
    ) -> FeedPage {
        playlists.forEach { playlistLookup[$0.id] = $0 }
        return FeedPage(
            videos: playlists.map { self.makePlaylistVideo(from: $0) },
            continuation: continuation
        )
    }

    func makePlaylistVideo(
        from playlist: Playlist
    ) -> Video {
        Video(
            id: playlist.id,
            title: playlist.title,
            channelId: nil,
            channelName: "common.playlist".localized,
            channelAvatarURL: nil,
            thumbnailURL: playlist.thumbnailURL ?? "",
            viewCount: playlist.itemCount.map {
                "common.videosCount".localized(with: $0)
            },
            publishedAt: nil,
            duration: nil,
            isLive: false
        )
    }

    func openPlaylist(
        _ playlist: Playlist
    ) {
        let controller = PlaylistVideosViewController(
            playlist: playlist,
            service: playlistsClient,
            channelViewControllerFactory: channelViewControllerFactory,
            videoRouter: videoRouter
        )
        let targetNav = navigationController?.parent?.navigationController
            ?? navigationController
        targetNav?.pushViewController(controller, animated: true)
    }

    func applyCollectionInsets(
        to collectionView: UICollectionView
    ) {
        let topInset = baseTabsInset()
        collectionView.contentInset.top = topInset
        collectionView.scrollIndicatorInsets.top = topInset
        collectionView.setContentOffset(
            CGPoint(x: 0, y: -topInset),
            animated: false
        )
    }

    func adjustCollectionInsetsForFilterBar() {
        guard let cv = collectionView else {
            return
        }
        let topInset = baseTabsInset() + ChannelFilterBarView.preferredHeight
        cv.contentInset.top = topInset
        cv.scrollIndicatorInsets.top = topInset
        cv.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
    }

    /// A channel with three videos can't scroll far enough to collapse
    /// the header: the list hits its end, springs back, and the header
    /// flickers open again. Pad the bottom until the whole collapse
    /// range is reachable.
    func padBottomInsetForCollapse() {
        guard let cv = collectionView else {
            return
        }
        let contentHeight = cv.collectionViewLayout
            .collectionViewContentSize.height
        let reachable = contentHeight + cv.adjustedContentInset.top
            + cv.adjustedContentInset.bottom - cv.contentInset.bottom
        let collapseRange = headerView.expandedHeight
            - headerView.collapsedHeight
        let pad = videoCount > 0
            ? max(0, cv.bounds.height + collapseRange - reachable)
            : 0
        guard abs(cv.contentInset.bottom - pad) > 0.5 else {
            return
        }
        cv.contentInset.bottom = pad
    }

    func updateScrollInsets(for scrollView: UIScrollView) {
        let extra = filterBar.isHidden ? 0 : ChannelFilterBarView.preferredHeight
        scrollView.scrollIndicatorInsets.top =
            (headerView.heightRef?.constant ?? 0)
            + ChannelTabsView.preferredHeight + extra
    }

    func baseTabsInset() -> CGFloat {
        headerView.expandedHeight + ChannelTabsView.preferredHeight
    }

    func updateInfoBarButton(for info: ChannelInfo) {
        let hasAbout = info.description != nil
            || info.contactInfo != nil
            || info.videoCountText != nil
        navigationItem.rightBarButtonItem = hasAbout
            ? infoBarButton : nil
    }
}
