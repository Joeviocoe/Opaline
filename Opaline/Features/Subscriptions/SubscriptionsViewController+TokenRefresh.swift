import UIKit

// MARK: - Token Refresh

extension SubscriptionsViewController {
    func observeTokenRefresh() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenRefresh),
            name: .tokenDidRefresh,
            object: nil
        )
    }

    @objc
    func handleTokenRefresh() {
        AppLog.subs("token refreshed → reloading feed")
        resetNewContentState()
        loadInitialContent()
    }

    /// Fires on sign-in too: drop the previous account's history
    /// snapshot so its dots don't leak into the new session.
    private func resetNewContentState() {
        newContentChannelIds = []
        newContentUploads = [:]
        newContentHistoryIds = nil
        newContentHistoryFetchedAt = nil
        locallyWatchedVideoIds = []
        channelBar.setNewContentChannelIds([])
        refreshNewContentDots()
    }
}
