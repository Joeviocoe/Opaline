import UIKit

class HomeViewController: VideosViewController {
    let service: FeedService
    let cache: AppCache
    /// Per-shelf continuation queue collected from parsed pages. When the
    /// section list runs out (~100 videos), pages get their continuation
    /// backfilled from here so scrolling keeps going (the Recommended
    /// shelf alone is effectively endless).
    var shelfQueue: [ShelfContinuation] = []
    /// True once pagination switched from the section list to shelf
    /// tokens. Failures then skip to the next shelf instead of
    /// retrying (a dead shelf token would stall the scroll forever).
    var isDrainingShelves = false
    /// Title of the shelf currently being drained — labels its pages.
    var drainTitle: String?
    var categories: [HomeCategory] = [.feed] + HomeCategory.destinations
    var selectedCategoryIndex = 0
    /// Unique shelf titles collected from feed pages, in order of
    /// first appearance — they become the dynamic chips.
    var shelfTitles: [String] = []
    /// Accumulated titled runs of the "All" feed; shelf chips filter
    /// these and "All" re-entry restores from them.
    var feedRuns: [FeedRun] = []
    /// The "All" feed's next continuation, preserved while a chip or
    /// destination page is shown.
    var allContinuation: String?
    /// Remaining same-title shelf tokens for the selected shelf chip.
    var chipTokens: [String] = []
    /// Non-nil while a dynamic shelf chip is selected.
    var selectedShelfTitle: String?
    /// True while background pages are being fetched to collect
    /// chips — the bar shows pulsing placeholders.
    var chipDiscoveryActive = false
    /// Background pages left to fetch for chip discovery.
    var chipPrefetchBudget = 0
    /// Shelf chip to re-select once a refresh lands.
    var pendingChipReselect: String?
    /// Bumped on every category switch / refresh; async completions
    /// compare it so a stale response can't overwrite the new feed.
    var feedGeneration = 0
    /// Session-lifetime cache so tab switches don't refetch.
    var categoryCache: [String: FeedPage] = [:]
    /// One rescue refetch per session when a cached token turns out dead.
    var didRevalidateAfterStaleToken = false
    lazy var chipBar = ChipBarView()

    override var groupsByShelf: Bool { HomeLayout.selected == .rails }

    override var useRails: Bool { HomeLayout.selected == .rails }

    override var columns: Int {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 1
        }
        let width = view.bounds.width
        if width < 500 {
            return 1
        }
        return width > view.bounds.height ? 3 : 2
    }

    lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.text = "home.error.loadFailed".localized
        label.textColor = .lightGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    lazy var signInEmptyView: SignInEmptyStateView = {
        let emptyView = SignInEmptyStateView(message: "home.signIn".localized)
        emptyView.isHidden = true
        emptyView.onSignIn = { [weak self] in self?.toolbarOpenProfile() }
        return emptyView
    }()

    init(
        service: FeedService,
        cache: AppCache = .shared,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> UIViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.service = service
        self.cache = cache
        super.init(
            channelViewControllerFactory: channelViewControllerFactory,
            videoRouter: videoRouter
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "home.title".localized
        AppLog.home("viewDidLoad")
        setupEmptyViews()
        setupChipBar()
        setupToolbar()
        observeSignOut()
        observeTokenRefresh()
        loadCachedOrFetchFeed()
    }

    @objc
    func handleSignOut() {
        ScreenVisitTracker.reset()
        cache.clearHomeFeed()
        categoryCache = [:]
        resetChipState()
        setPage(FeedPage(videos: [], continuation: nil))
        toolbarRefreshProfileButton()
        chipBar.setSelected(0)
        selectCategory(at: 0)
    }

    override func handleRefresh() {
        feedGeneration += 1
        switch categories[selectedCategoryIndex].kind {
        case .destination(let browseId):
            categoryCache[browseId] = nil
            loadCategory(browseId)
        case .shelf:
            pendingChipReselect = selectedShelfTitle
            refreshAllFeed()
        case .feed, .placeholder:
            refreshAllFeed()
        }
    }

    override func loadRailPage(
        token: String,
        completion: @escaping (FeedPage?) -> Void
    ) {
        let generation = feedGeneration
        service.fetchNextPage(continuation: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.feedGeneration == generation else {
                    completion(nil)
                    return
                }
                var page = try? result.get()
                // A chip's rail chains into the next same-title token
                // once its own shelf runs dry.
                if self.selectedShelfTitle != nil,
                   var chained = page,
                   chained.continuation == nil,
                   !self.chipTokens.isEmpty {
                    chained.continuation = self.chipTokens.removeFirst()
                    page = chained
                }
                completion(page)
            }
        }
    }

    override func handleLoadMore() {
        if selectedShelfTitle != nil {
            loadMoreForChip()
            return
        }
        guard let continuation = currentContinuation else {
            finishLoadingMore()
            return
        }
        let generation = feedGeneration
        service.fetchNextPage(continuation: continuation) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.feedGeneration == generation else {
                    return
                }
                switch result {
                case .success(let page):
                    self.appendPage(self.enqueueShelves(from: page))
                    self.continueChipPrefetchIfNeeded()
                case .failure where self.isDrainingShelves:
                    self.appendPage(self.backfilled(
                        FeedPage(videos: [], continuation: nil)
                    ))
                    self.continueChipPrefetchIfNeeded()
                case .failure:
                    self.finishLoadingMore()
                    self.endChipDiscovery()
                    self.revalidateOnceAfterStaleToken()
                }
            }
        }
    }
}
