import UIKit

/// A titled group of videos rendered as one collection-view section.
struct VideoSection {
    let title: String?
    var videos: [Video]
    /// The shelf's own token — rails page horizontally with it.
    var continuation: String?
}

// MARK: - Section Accessors

extension VideosViewController {
    func video(at indexPath: IndexPath) -> Video {
        sections[indexPath.section].videos[indexPath.item]
    }

    /// Number of videos after the given index path (for the
    /// load-more trigger).
    func videosRemaining(after indexPath: IndexPath) -> Int {
        var remaining = sections[indexPath.section].videos.count
            - indexPath.item - 1
        for section in sections.dropFirst(indexPath.section + 1) {
            remaining += section.videos.count
        }
        return remaining
    }

    func openChannel(for video: Video) {
        guard let channelId = video.channelId else {
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

    func presentVideoMenu(_ video: Video, anchor: UIView) {
        VideoActionMenu.present(video: video, from: self, anchor: anchor)
    }

    func endRefreshing() {
        collectionView?.refreshControl?.endRefreshing()
    }

    func updateItemSize() {
        guard let collectionView,
              let layout = collectionView
                  .collectionViewLayout
                  as? UICollectionViewFlowLayout
        else {
            return
        }
        let inset = layout.sectionInset.left
            + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing
            * CGFloat(max(columns - 1, 0))
        let available = collectionView.bounds.width
            - inset - spacing
        let width = floor(available / CGFloat(columns))
        let height: CGFloat = width * (9.0 / 16.0) + 92
        let newSize = CGSize(
            width: width,
            height: height
        )
        if layout.itemSize != newSize {
            layout.itemSize = newSize
            layout.invalidateLayout()
        }
    }
}

// MARK: - UICollectionViewDataSource

extension VideosViewController: UICollectionViewDataSource {
    func numberOfSections(
        in collectionView: UICollectionView
    ) -> Int {
        isLoadingInitial ? 1 : sections.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        if isLoadingInitial {
            return VideosViewController.skeletonCount
        }
        return useRails ? 1 : sections[section].videos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if !isLoadingInitial, useRails {
            return railCell(in: collectionView, at: indexPath)
        }
        guard let cell = collectionView
            .dequeueReusableCell(
                withReuseIdentifier: VideoCell.reuseId,
                for: indexPath
            ) as? VideoCell
        else {
            return UICollectionViewCell()
        }
        cell.forceGridLayout = true
        if isLoadingInitial {
            cell.configureSkeleton()
            return cell
        }
        let video = video(at: indexPath)
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            self?.openChannel(for: video)
        }
        cell.onMenuTap = { [weak self] anchor in
            self?.presentVideoMenu(video, anchor: anchor)
        }
        return cell
    }

    private func railCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShelfRailCell.reuseId,
            for: indexPath
        ) as? ShelfRailCell else {
            return UICollectionViewCell()
        }
        let section = indexPath.section
        cell.configure(with: sections[section].videos)
        cell.onVideoTap = { [weak self] video in
            self?.openVideo(video)
        }
        cell.onChannelTap = { [weak self] video in
            self?.openChannel(for: video)
        }
        cell.onMenuTap = { [weak self] video, anchor in
            self?.presentVideoMenu(video, anchor: anchor)
        }
        cell.onNearEnd = { [weak self] in
            self?.loadMoreInRail(section: section)
        }
        return cell
    }

    /// Horizontal pagination: extends the rail with its shelf's next
    /// page when the user scrolls near its trailing edge.
    private func loadMoreInRail(section: Int) {
        guard section < sections.count,
              let token = sections[section].continuation,
              !loadingRailSections.contains(section)
        else {
            return
        }
        loadingRailSections.insert(section)
        loadRailPage(token: token) { [weak self] page in
            self?.finishRailLoad(section: section, page: page)
        }
    }

    private func finishRailLoad(section: Int, page: FeedPage?) {
        loadingRailSections.remove(section)
        guard let page, section < sections.count else {
            return
        }
        let added = appendToRail(
            page.videos,
            section: section,
            continuation: page.continuation
        )
        guard !added.isEmpty else {
            return
        }
        let cell = collectionView?.cellForItem(
            at: IndexPath(item: 0, section: section)
        ) as? ShelfRailCell
        cell?.appendVideos(added)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let header = collectionView.dequeueReusableSupplementaryView(
                  ofKind: kind,
                  withReuseIdentifier: VideoSectionHeaderView.reuseId,
                  for: indexPath
              ) as? VideoSectionHeaderView
        else {
            return UICollectionReusableView()
        }
        let title = isLoadingInitial
            ? nil : sections[indexPath.section].title
        header.configure(title: title)
        return header
    }
}
