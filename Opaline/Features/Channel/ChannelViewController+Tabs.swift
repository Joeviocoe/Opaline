import UIKit

extension ChannelViewController {
    func installTabsView() {
        guard let cv = collectionView else {
            return
        }
        tabsView.onTabSelected = { [weak self] tab in
            self?.selectTab(tab)
        }
        view.addSubview(tabsView)
        NSLayoutConstraint.activate([
            tabsView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tabsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabsView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        topBarHider.onChange = { [weak self] hidden in
            self?.applyTopChromeHidden(hidden)
        }
        installFilterBar()
        applyCollectionInsets(to: cv)
    }

    /// Runs inside the top-bar hide/show animation — the tabs and the
    /// filter chips slide away together with the navigation bar.
    func applyTopChromeHidden(_ hidden: Bool) {
        let tabsShift = ChannelTabsView.preferredHeight
        tabsView.alpha = hidden ? 0 : 1
        tabsView.transform = hidden
            ? CGAffineTransform(translationX: 0, y: -tabsShift)
            : .identity
        filterBar.alpha = hidden ? 0 : 1
        filterBar.transform = hidden
            ? CGAffineTransform(
                translationX: 0,
                y: -(tabsShift + ChannelFilterBarView.preferredHeight)
            )
            : .identity
    }

    func installFilterBar() {
        filterBar.isHidden = true
        filterBar.onSelect = { [weak self] index in
            self?.handleChipSelected(at: index)
        }
        view.addSubview(filterBar)
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: tabsView.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func selectTab(_ tab: ChannelTabsView.Tab) {
        guard tab != currentTab else {
            return
        }
        currentTab = tab
        // Shorts and videos have different card shapes; the layout has to be
        // recomputed before the new tab's items arrive.
        updateItemSize()
        filterChips = []
        filterBar.clearTitles()
        filterBar.isHidden = true
        loadCurrentTab()
    }

    func loadCurrentTab() {
        beginTabLoad()
        switch currentTab {
        case .videos:
            loadVideoTab(params: ChannelTabParams.videos)
        case .shorts:
            loadVideoTab(params: ChannelTabParams.shorts)
        case .live:
            loadVideoTab(params: ChannelTabParams.live)
        case .playlists:
            loadPlaylistTab()
        }
    }

    func beginTabLoad() {
        playlistLookup = [:]
        spinner.startAnimating()
        isLoadingInitial = true
        errorLabel.isHidden = true
        collectionView?.reloadData()
    }

    func loadVideoTab(params: String) {
        let expectedTab = currentTab
        tabsClient.fetchChannelTab(
            channelId: channelId,
            params: params
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self
                else { return }
                guard self.currentTab == expectedTab
                else { return }
                self.handleSelectedTabVideos(result)
            }
        }
    }

    func loadPlaylistTab() {
        let expectedTab = currentTab
        tabsClient.fetchChannelPlaylists(
            channelId: channelId,
            params: ChannelTabParams.playlists
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    return
                }
                self?.handleSelectedTabPlaylists(result)
            }
        }
    }

    func handleSelectedTabVideos(
        _ result: Result<ChannelTabPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let tabPage):
            setPage(tabPage.feedPage)
            errorLabel.isHidden = videoCount > 0
            applyFilterChips(tabPage.filterChips)
        case .failure(let error):
            AppLog.channel("tab load failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            errorLabel.isHidden = false
        }
    }

    func handleSelectedTabPlaylists(
        _ result: Result<PlaylistsPage, Error>
    ) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let page):
            let feedPage = playlistFeedPage(from: page.playlists, continuation: page.continuation)
            setPage(feedPage)
            applyFilterChips(page.filterChips)
            errorLabel.isHidden = !page.playlists.isEmpty
        case .failure(let error):
            AppLog.channel("playlist tab failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            errorLabel.isHidden = false
        }
    }

    func applyFilterChips(_ chips: [ChannelFilterChip]) {
        guard !chips.isEmpty else {
            return
        }
        filterChips = chips
        filterBar.setTitles(chips.map { $0.label }, selected: 0)
        filterBar.isHidden = false
        adjustCollectionInsetsForFilterBar()
    }

    func loadMoreVideos(continuation: String) {
        let expectedTab = currentTab
        tabsClient.fetchChannelTabNextPage(
            continuation: continuation
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    self?.finishLoadingMore()
                    return
                }
                self?.handlePageResult(result)
            }
        }
    }

    func handleChipSelected(at index: Int) {
        guard index < filterChips.count else {
            return
        }
        switch filterChips[index].action {
        case .continuation(let token):
            loadSortedVideoTab(token: token)
        case .browse(let action):
            loadSortedBrowseTab(channelId: action.channelId, params: action.params)
        }
    }

    func loadSortedVideoTab(token: String) {
        let expectedTab = currentTab
        spinner.startAnimating()
        isLoadingInitial = true
        collectionView?.reloadData()
        tabsClient.fetchChannelTabNextPage(
            continuation: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab
                else { return }
                self?.spinner.stopAnimating()
                switch result {
                case .success(let page):
                    self?.setPage(page)
                case .failure(let error):
                    AppLog.channel("sort failed: \(error)")
                }
            }
        }
    }

    func loadSortedBrowseTab(channelId: String, params: String) {
        let expectedTab = currentTab
        spinner.startAnimating()
        isLoadingInitial = true
        collectionView?.reloadData()
        tabsClient.fetchChannelPlaylists(
            channelId: channelId,
            params: params
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab
                else { return }
                self?.spinner.stopAnimating()
                switch result {
                case .success(let page):
                    let feedPage = self?.playlistFeedPage(
                        from: page.playlists,
                        continuation: page.continuation
                    )
                    if let feedPage { self?.setPage(feedPage) }
                case .failure(let error):
                    AppLog.channel("sort browse failed: \(error)")
                }
            }
        }
    }

    func loadMorePlaylists(continuation: String) {
        let expectedTab = currentTab
        tabsClient.fetchChannelPlaylistsNextPage(
            continuation: continuation
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard self?.currentTab == expectedTab else {
                    self?.finishLoadingMore()
                    return
                }
                switch result {
                case .success(let page):
                    let feedPage = self?.playlistFeedPage(
                        from: page.playlists,
                        continuation: page.continuation
                    ) ?? FeedPage(videos: [], continuation: nil)
                    self?.appendPage(feedPage)
                case .failure:
                    self?.finishLoadingMore()
                }
            }
        }
    }
}
