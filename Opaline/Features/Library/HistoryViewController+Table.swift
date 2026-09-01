import UIKit

// MARK: - DataSource / Delegate

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isLoadingInitial ? HistoryViewController.skeletonCount : videos.count
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
        if isLoadingInitial {
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
            let targetNav = self.navigationController?.parent?
                .navigationController ?? self.navigationController
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
                onRemoved: { [weak self] in
                    self?.removeVideoFromList(id: video.id)
                },
                feedbackOutcome: .removed
            )
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isLoadingInitial else {
            return
        }
        let video = videos[indexPath.row]
        videoRouter.open(video: video, from: self)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let title = isLoadingInitial ? "" : videos[indexPath.row].title
        return SubscriptionVideoCell.rowHeight(forWidth: tableView.bounds.width, title: title)
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard !isLoadingInitial, !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 5
        else {
            return
        }
        loadMore()
    }
}
