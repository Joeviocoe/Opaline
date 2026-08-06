import UIKit

// MARK: - Subscribed Channels Data

extension SubscriptionsViewController {
    func loadSubscribedChannels(force: Bool = false) {
        guard !OAuthClient.shared.isAnonymous else {
            return
        }
        if force {
            fetchSubscribedChannelsFromNetwork()
            return
        }
        cache.loadSubscribedChannels { [weak self] cached in
            if let cached, !cached.isEmpty {
                self?.applyChannels(cached)
            } else {
                self?.fetchSubscribedChannelsFromNetwork()
            }
        }
    }

    /// Harvests channels shipped inside the subscriptions feed
    /// response, falling back to channels derived from the loaded
    /// videos so the bar appears even if no channel row is served.
    func harvestChannels(from page: FeedPage) {
        if let pageChannels = page.channels, !pageChannels.isEmpty {
            let merged = mergedChannels(
                primary: pageChannels,
                secondary: subscribedChannels
            )
            applyChannels(merged)
            cache.setSubscribedChannels(merged)
            return
        }
        guard subscribedChannels.isEmpty else {
            return
        }
        let derived = channelsDerived(from: page.videos)
        if !derived.isEmpty {
            AppLog.subs("channel bar: derived \(derived.count) from feed")
            applyChannels(derived)
        }
    }

    func applyChannels(_ channels: [SubscribedChannel]) {
        subscribedChannels = channels
        guard !channels.isEmpty else {
            return
        }
        channelBar.setChannels(channels)
        channelBar.setSelectedChannelId(selectedChannel?.id)
        refreshNewContentDots()
        if tableView.tableHeaderView !== channelBar {
            channelBar.frame = CGRect(
                x: 0,
                y: 0,
                width: tableView.bounds.width,
                height: ChannelAvatarBarView.preferredHeight
            )
            tableView.tableHeaderView = channelBar
        }
    }
}

// MARK: - Private Helpers

private extension SubscriptionsViewController {
    func fetchSubscribedChannelsFromNetwork() {
        channelsService.fetchSubscribedChannels { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                switch result {
                case .success(let channels):
                    let merged = self.mergedChannels(
                        primary: self.subscribedChannels,
                        secondary: channels
                    )
                    self.cache.setSubscribedChannels(merged)
                    self.applyChannels(merged)
                case .failure(let error):
                    AppLog.subs("channels load failed: \(error)")
                }
            }
        }
    }

    /// Primary keeps its order (recency); secondary fills in the rest.
    func mergedChannels(
        primary: [SubscribedChannel],
        secondary: [SubscribedChannel]
    ) -> [SubscribedChannel] {
        guard !primary.isEmpty else {
            return secondary
        }
        let primaryIds = Set(primary.map { $0.id })
        return primary + secondary.filter {
            !primaryIds.contains($0.id)
        }
    }

    func channelsDerived(from videos: [Video]) -> [SubscribedChannel] {
        var seenIds: Set<String> = []
        var channels: [SubscribedChannel] = []
        for video in videos {
            guard let id = video.channelId,
                  !video.channelName.isEmpty,
                  seenIds.insert(id).inserted
            else { continue }
            channels.append(
                SubscribedChannel(
                    id: id,
                    title: video.channelName,
                    avatarURL: video.channelAvatarURL
                )
            )
        }
        return channels
    }
}
