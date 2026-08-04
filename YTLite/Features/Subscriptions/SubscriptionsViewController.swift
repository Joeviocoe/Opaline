import UIKit

class SubscriptionsViewController: UIViewController, ScrollableToTop {
    static let skeletonCount = 6
    let service: FeedService
    let channelTabsService: ChannelTabService
    let channelsService: SubscribedChannelsService
    let historyService: HistoryService
    let channelRSSService: ChannelRSSFeedService
    let cache: AppCache
    let channelViewControllerFactory: (
        String,
        String
    ) -> UIViewController
    let videoRouter: VideoRouter
    var videos: [Video] = []
    var continuationToken: String?
    var isLoadingMore = false
    var seenVideoIds: Set<String> = []
    var sortDatesByVideoId: [String: Date] = [:]
    let tableView = UITableView()
    let spinner = UIActivityIndicatorView(style: .white)
    let channelBar = ChannelAvatarBarView()
    var subscribedChannels: [SubscribedChannel] = []
    var selectedChannel: SubscribedChannel?
    var stashedVideos: [Video] = []
    var stashedContinuation: String?
    var stashedSeenVideoIds: Set<String> = []
    var isLoadingInitial = true
    var signInPrompt: SignInEmptyStateView?
    lazy var topBarHider = TopBarAutoHider(owner: self)
    // New-content dots (issue #13): derived state, never persisted.
    var newContentChannelIds: Set<String> = []
    var newContentUploads: [String: [RSSVideoEntry]] = [:]
    var newContentHistoryIds: Set<String>?
    var newContentHistoryFetchedAt: Date?
    var isLoadingNewContentHistory = false
    var isLoadingNewContentRSS = false
    var locallyWatchedVideoIds: Set<String> = []
    /// Once per session — mirrors `HomeViewController`'s guard so a dead
    /// cached continuation triggers exactly one lazy revalidation.
    var didRevalidateAfterStaleToken = false

    init(
        dependencies: AppDependencies,
        cache: AppCache = .shared,
        videoRouter: VideoRouter = .shared
    ) {
        service = dependencies.feedService
        channelTabsService = dependencies.channelTabService
        channelsService = dependencies.subscribedChannelsService
        historyService = dependencies.historyService
        channelRSSService = dependencies.channelRSSService
        channelViewControllerFactory = dependencies.makeChannelViewController
        self.cache = cache
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "subscriptions.title".localized
        AppLog.subs("viewDidLoad")
        setupTableView()
        setupSpinner()
        setupSignInPrompt()
        setupChannelBar()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowShortsChange),
            name: .showShortsSettingDidChange,
            object: nil
        )
        ToolbarManager.shared.install(in: self)
        observeTokenRefresh()
        loadInitialContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChannelBarFrame()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshNewContentDots()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        topBarHider.showBars()
    }

    func scrollToTop() {
        topBarHider.showBars()
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
            animated: true
        )
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        channelBar.applyTheme()
        tableView.reloadData()
    }

    @objc
    func handleRefresh() {
        if let channel = selectedChannel {
            loadChannelVideos(channel)
            return
        }
        cache.clearSubscriptionsFeed()
        cache.clearSubscribedChannels()
        loadFeed()
        loadSubscribedChannels(force: true)
    }

    @objc
    func handleShowShortsChange() {
        cache.clearSubscriptionsFeed()
        loadFeed()
        newContentUploads = [:]
        refreshNewContentDots()
    }
}

extension SubscriptionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isLoadingInitial ? SubscriptionsViewController.skeletonCount : videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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
            guard let self,
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
            guard let self else {
                return
            }
            VideoActionMenu.present(video: video, from: self, anchor: anchor)
        }
    }
}

extension SubscriptionsViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }
        topBarHider.handleScroll(scrollView)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isLoadingInitial else {
            return
        }
        let video = videos[indexPath.row]
        markWatchedLocally(video)
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
        guard !isLoadingInitial,
              !isLoadingMore,
              continuationToken != nil,
              indexPath.row >= videos.count - 4
        else { return }

        isLoadingMore = true
        loadMore()
    }
}
