import UIKit

// MARK: - Channel page loading

extension ChannelViewController {
    func restoreFromCache() {
        let cid = channelId
        if let info = cache.cachedChannelInfo(channelId: cid) {
            applyChannelInfo(info)
        }
        if let page = cache.cachedChannelPage(channelId: cid) {
            spinner.stopAnimating()
            applyChannelPage(page)
        }
    }

    func loadChannel() {
        errorLabel.isHidden = true
        client.fetchChannelPage(
            channelId: channelId
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleChannelResult(result)
            }
        }
    }

    private func handleChannelResult(
        _ result: Result<ChannelPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let page):
            applyChannelPage(page)
            loadCurrentTab()
            enrichFromWeb(pageInfo: page)
        case .failure(let error):
            AppLog.channel("load failed \(channelId): \(error)")
            finishLoadingMore()
            errorLabel.isHidden = videoCount > 0
        }
    }

    private func enrichFromWeb(pageInfo: ChannelPage) {
        client.enrichChannelInfo(
            channelId: channelId,
            tvInfo: pageInfo.info
        ) { [weak self] info in
            self?.applyChannelInfo(info)
        }
    }

    func handlePageResult(
        _ result: Result<FeedPage, Error>
    ) {
        switch result {
        case .success(let page):
            appendPage(page)
        case .failure(let error):
            AppLog.channel(
                "pagination failed \(channelId): \(error)"
            )
            finishLoadingMore()
        }
    }
}
