import UIKit

// MARK: - Results / panel table

extension SearchViewController: UITableViewDataSource {
    private static let panelCellId = "SearchPanelCell"
    private static let panelRowHeight: CGFloat = 44

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        panelMode == .hidden ? results.count : panelItems.count
    }

    func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        panelMode == .history && !panelItems.isEmpty
            ? "search.recent".localized
            : nil
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if panelMode != .hidden {
            return panelCell(tableView, indexPath: indexPath)
        }
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscriptionVideoCell.reuseId,
            for: indexPath
        ) as? SubscriptionVideoCell else {
            return UITableViewCell()
        }
        let video = results[indexPath.row]
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
            self.navigationController?.pushViewController(
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
                anchor: anchor
            ) { [weak self] in
                self?.results.removeAll { $0.id == video.id }
                self?.tableView.reloadData()
            }
        }
    }

    private func panelCell(
        _ tableView: UITableView,
        indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.panelCellId
        ) ?? UITableViewCell(
            style: .default,
            reuseIdentifier: Self.panelCellId
        )
        let theme = ThemeManager.shared
        cell.backgroundColor = theme.background
        cell.textLabel?.textColor = theme.primaryText
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.textLabel?.text = panelItems[indexPath.row]
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        panelMode == .history
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard panelMode == .history,
              editingStyle == .delete else {
            return
        }
        removeHistoryItem(at: indexPath.row)
    }
}

extension SearchViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        if panelMode != .hidden {
            tableView.deselectRow(at: indexPath, animated: true)
            executePanelQuery(panelItems[indexPath.row])
            return
        }
        let video = results[indexPath.row]
        videoRouter.open(video: video, from: self)
    }

    func tableView(
        _ tableView: UITableView,
        willDisplayHeaderView view: UIView,
        forSection section: Int
    ) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor =
            ThemeManager.shared.secondaryText
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        guard panelMode == .hidden else {
            return Self.panelRowHeight
        }
        return SubscriptionVideoCell.rowHeight(
            forWidth: tableView.bounds.width,
            title: results[indexPath.row].title,
            hasDuration: results[indexPath.row].duration?.isEmpty == false
        )
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard panelMode == .hidden,
              indexPath.row >= results.count - 4 else {
            return
        }
        loadNextPage()
    }
}
