import UIKit

// MARK: - DataSource / Delegate

extension PlaylistVideosViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isLoading ? PlaylistVideosViewController.skeletonCount : videos.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscriptionVideoCell.reuseId,
            for: indexPath
        ) as? SubscriptionVideoCell else {
            return UITableViewCell()
        }
        if isLoading {
            cell.configureSkeleton()
            return cell
        }
        let video = videos[indexPath.row]
        cell.configure(with: video)
        attachHandlers(to: cell, video: video)
        return cell
    }

    private func attachHandlers(to cell: SubscriptionVideoCell, video: Video) {
        cell.onChannelTap = { [weak self] in
            guard let self = self,
                  let channelId = video.channelId
            else {
                return
            }
            let parentNav = self.navigationController?.parent?.navigationController
            let targetNav = parentNav ?? self.navigationController
            targetNav?.pushViewController(
                self.channelViewControllerFactory(
                    channelId,
                    video.channelName
                ),
                animated: true
            )
        }
        cell.onMenuTap = { [weak self] anchor in
            guard let self = self else {
                return
            }
            VideoActionMenu.present(
                video: video,
                from: self,
                anchor: anchor,
                removeFrom: (id: self.playlist.id, title: self.playlist.title)
            ) { [weak self] in
                self?.removeVideoFromList(videoId: video.id)
            }
        }
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard !isLoading else {
            return
        }
        if indexPath.row >= videos.count - 4 {
            loadMoreVideos()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isLoading else {
            return
        }
        let video = videos[indexPath.row]
        videoRouter.open(video: video, from: self)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let title = isLoading ? "" : videos[indexPath.row].title
        return SubscriptionVideoCell.rowHeight(forWidth: tableView.bounds.width, title: title)
    }
}
