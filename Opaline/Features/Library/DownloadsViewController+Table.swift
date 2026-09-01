import UIKit

// MARK: - DataSource / Delegate

extension DownloadsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        videos.count
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
        let video = videos[indexPath.row]
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            self?.openChannel(for: video)
        }
        cell.onMenuTap = { [weak self] anchor in
            guard let self = self else {
                return
            }
            VideoActionMenu.present(video: video, from: self, anchor: anchor)
        }
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        open(videos[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        SubscriptionVideoCell.rowHeight(
            forWidth: tableView.bounds.width,
            title: videos[indexPath.row].title
        )
    }
}
