import UIKit

// MARK: - Local watch history
//
// The signed-out History screen. It reads `LocalHistoryStore` directly
// rather than going through `HistoryService`, because nothing about the
// account path transfers: its pagination needs a live OAuth token, its
// delete is a server-issued feedback token per row, and its every page is
// written into the shared `AppCache` history slot, where local entries would
// later be served as the account's.
//
// The payoff for branching honestly is that none of those guards are needed
// here at all.

extension HistoryViewController {
    func setupLocalHistory() {
        spinner.stopAnimating()
        isLoadingInitial = false
        continuationToken = nil
        installClearAllButton()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localHistoryDidChange),
            name: LocalHistoryStore.didChangeNotification,
            object: nil
        )
        reloadLocalHistory()
        AppLog.library("history screen: local, \(videos.count) videos")
    }

    @objc
    func localHistoryDidChange() {
        reloadLocalHistory()
    }

    func reloadLocalHistory() {
        videos = LocalHistoryStore.shared.videos
        emptyLabel.text = "library.history.local.empty".localized
        emptyLabel.isHidden = !videos.isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !videos.isEmpty
        tableView.reloadData()
    }

    private func installClearAllButton() {
        let button = UIBarButtonItem(
            title: "library.history.clearAll".localized,
            style: .plain,
            target: self,
            action: #selector(confirmClearLocalHistory)
        )
        navigationItem.rightBarButtonItem = button
    }

    @objc
    func confirmClearLocalHistory() {
        let alert = UIAlertController(
            title: "library.history.clearAll".localized,
            message: "library.history.clearAll.confirm".localized,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "common.cancel".localized, style: .cancel)
        )
        alert.addAction(
            UIAlertAction(
                title: "library.history.clearAll".localized,
                style: .destructive
            ) { _ in
                LocalHistoryStore.shared.clear()
                // Or every card keeps its red progress bar and visibly
                // contradicts the action just taken.
                WatchProgressStore.shared.clearAll()
                AppLog.library("history screen: cleared by user")
            }
        )
        present(alert, animated: true)
    }
}

// MARK: - Swipe to delete

extension HistoryViewController {
    /// `canEditRowAt` + `commit:forRowAt:` rather than
    /// `trailingSwipeActionsConfigurationForRowAt`, which is iOS 11.
    func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        LocalLibrary.isActive
            && !isLoadingInitial
            && indexPath.row < videos.count
    }

    func tableView(
        _ tableView: UITableView,
        titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath
    ) -> String? {
        "common.delete".localized
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete,
              LocalLibrary.isActive,
              indexPath.row < videos.count
        else {
            return
        }
        let video = videos[indexPath.row]
        videos.remove(at: indexPath.row)
        // The row goes first, then the store — the store's change
        // notification would otherwise reload the table mid-animation.
        tableView.deleteRows(at: [indexPath], with: .automatic)
        LocalHistoryStore.shared.remove(videoId: video.id)
        emptyLabel.isHidden = !videos.isEmpty
    }
}
