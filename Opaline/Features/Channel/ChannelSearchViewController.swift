import UIKit

/// Results for a search restricted to one channel. Reuses the shared video
/// grid so paging, theming and Shorts handling come for free; the query
/// lives in a search bar standing in for the navigation title.
final class ChannelSearchViewController: VideosViewController {
    private let channelId: String
    private let service: ChannelTabService
    private let searchBar = UISearchBar()
    private let emptyLabel = UILabel()
    private var query = ""

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

    init(
        channelId: String,
        service: ChannelTabService,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> UIViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.channelId = channelId
        self.service = service
        super.init(
            channelViewControllerFactory: channelViewControllerFactory,
            videoRouter: videoRouter
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        isLoadingInitial = false
        spinner.stopAnimating()
        setupSearchBar()
        setupEmptyLabel()
        applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if query.isEmpty {
            searchBar.becomeFirstResponder()
        }
    }

    override func applyTheme() {
        super.applyTheme()
        let theme = ThemeManager.shared
        searchBar.barStyle = theme.barStyle
        searchBar.keyboardAppearance = theme.isDark ? .dark : .default
        emptyLabel.textColor = theme.secondaryText
    }

    override func handleRefresh() {
        guard !query.isEmpty else {
            endRefreshing()
            return
        }
        runSearch(query)
    }

    override func handleLoadMore() {
        guard let token = currentContinuation else {
            finishLoadingMore()
            return
        }
        let text = query
        service.fetchChannelSearchNextPage(
            continuation: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                // Same staleness guard as runSearch: a late page of the
                // previous query must not splice into the new one.
                guard let self = self, self.query == text else {
                    return
                }
                guard case .success(let page) = result else {
                    self.finishLoadingMore()
                    return
                }
                self.appendPage(page)
            }
        }
    }

    // MARK: - Setup

    private func setupSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "search.title".localized
        navigationItem.titleView = searchBar
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "search.noResults".localized
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Search

    private func runSearch(_ text: String) {
        query = text
        emptyLabel.isHidden = true
        isLoadingInitial = true
        spinner.startAnimating()
        collectionView?.reloadData()
        service.fetchChannelSearch(
            channelId: channelId,
            query: text
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.query == text else {
                    return
                }
                self.applyResult(result)
            }
        }
    }

    private func applyResult(_ result: Result<FeedPage, Error>) {
        spinner.stopAnimating()
        endRefreshing()
        switch result {
        case .success(let page):
            setPage(page)
            emptyLabel.isHidden = !page.videos.isEmpty
        case .failure(let error):
            AppLog.channel("search failed \(channelId): \(error)")
            setPage(FeedPage(videos: [], continuation: nil))
            emptyLabel.isHidden = false
        }
    }
}

// MARK: - UISearchBarDelegate

extension ChannelSearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = (searchBar.text ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else {
            return
        }
        searchBar.resignFirstResponder()
        runSearch(text)
    }
}
