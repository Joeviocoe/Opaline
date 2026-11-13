import UIKit

// MARK: - Refresh progress on the avatar bar
//
// The local feed is rebuilt one channel at a time, and the walk reports
// each channel as it starts and ends. That progress is drawn as a spinning
// arc around the channel's own avatar — so the refresh shows *where* it is
// rather than occupying a row of its own above the list.

extension SubscriptionsViewController {
    func observeChannelRefreshProgress() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(channelFetchDidStart),
            name: LocalChannelUploads.channelFetchDidStartNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(channelFetchDidEnd),
            name: LocalChannelUploads.channelFetchDidEndNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(channelWalkDidFinish),
            name: LocalChannelUploads.walkDidFinishNotification,
            object: nil
        )
    }

    @objc
    func channelFetchDidStart(_ notification: Notification) {
        guard let id = channelId(in: notification) else {
            return
        }
        setChannelRefreshing(id, true)
    }

    @objc
    func channelFetchDidEnd(_ notification: Notification) {
        guard let id = channelId(in: notification) else {
            return
        }
        setChannelRefreshing(id, false)
        walkCompletedCount += 1
        updateFeedStatus()
    }

    /// Belt and braces: a walk that ends leaves nothing spinning, whatever
    /// the start/end pairing did.
    @objc
    func channelWalkDidFinish() {
        walkCompletedCount = 0
        refreshingChannelIds = []
        channelBar.setRefreshingChannelIds([])
        updateFeedStatus()
    }

    /// The line under the All button: progress while a walk runs, and
    /// otherwise when the feed was last rebuilt. The time is the local
    /// cache's own stamp, written by every successful walk, so it survives a
    /// relaunch and needs no clock of its own.
    func updateFeedStatus() {
        guard LocalLibrary.isActive else {
            channelBar.setStatus(nil)
            return
        }
        if walkCompletedCount > 0 || !refreshingChannelIds.isEmpty {
            let total = max(subscribedChannels.count, walkCompletedCount)
            channelBar.setStatus(
                "subscriptions.status.updating".localized(
                    with: min(walkCompletedCount, total), total
                )
            )
            return
        }
        guard let age = cache.localSubscriptionsFeedAge() else {
            channelBar.setStatus(nil)
            return
        }
        let when = SubscriptionsViewController.statusTimeFormatter.string(
            from: Date().addingTimeInterval(-age)
        )
        channelBar.setStatus(
            "subscriptions.status.updated".localized(with: when)
        )
    }

    private static let statusTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func setChannelRefreshing(_ channelId: String, _ refreshing: Bool) {
        if refreshing {
            refreshingChannelIds.insert(channelId)
        } else {
            refreshingChannelIds.remove(channelId)
        }
        channelBar.setRefreshingChannelIds(refreshingChannelIds)
    }

    /// How far past the top a drag has to go to count as a pull-to-refresh
    /// when there is no `UIRefreshControl` to decide it. Matches the
    /// control's own feel.
    static let pullToRefreshDistance: CGFloat = 80

    /// Local mode has no `UIRefreshControl`: holding one for a twenty-second
    /// walk shoved the list down and then jumped it the instant the refresh
    /// landed, under a finger about to tap; releasing it early still showed
    /// its row for a beat after the finger lifted. The avatars carry the
    /// progress, so the pull is read straight off the scroll view instead
    /// and the list simply springs back.
    func handlePullIfPastThreshold(_ scrollView: UIScrollView) {
        guard tableView.refreshControl == nil else {
            return
        }
        let pulled = -(scrollView.contentOffset.y
            + scrollView.adjustedContentInset.top)
        guard pulled >= SubscriptionsViewController.pullToRefreshDistance
        else {
            return
        }
        AppLog.subs("pull-to-refresh (\(Int(pulled))pt)")
        handleRefresh()
    }

    private func channelId(in notification: Notification) -> String? {
        notification.userInfo?[LocalChannelUploads.channelIdKey] as? String
    }
}
