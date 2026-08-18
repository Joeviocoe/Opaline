import UIKit

class SearchViewController: UIViewController {
    let service: SearchService
    let channelViewControllerFactory: (
        String,
        String
    ) -> UIViewController
    let videoRouter: VideoRouter
    var results: [Video] = []
    var filters = SearchFilters()
    let filtersButton = UIBarButtonItem(
        title: "search.filters".localized, style: .plain, target: nil, action: nil
    )
    var lastQuery: String = ""
    var activeSearchQuery: String?
    var searchCancellationToken = CancellationToken()
    var continuationToken: String?
    var isLoadingNextPage = false
    var panelMode: PanelMode = .hidden
    var suggestions: [String] = []
    var suggestWorkItem: DispatchWorkItem?
    var suggestToken = CancellationToken()
    let searchHistory = SearchHistoryStore.shared

    let searchBar = UISearchBar()
    let tableView = UITableView()
    let refreshControl = UIRefreshControl()
    lazy var topBarHider = TopBarAutoHider(owner: self)

    init(
        service: SearchService,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> UIViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.service = service
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "search.title".localized
        setupFiltersButton()
        setupSearchBar()
        setupTableView()
        applyTheme()
        showHistoryIfIdle()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Only on a fresh screen: coming back from a video should leave
        // the results where they were, without the keyboard covering them.
        if results.isEmpty {
            searchBar.becomeFirstResponder()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        topBarHider.showBars()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // The same table renders the suggestions panel — keep the top
        // bar while the user is picking a query.
        guard scrollView === tableView, panelMode == .hidden else {
            return
        }
        topBarHider.handleScroll(scrollView)
    }

    private func setupSearchBar() {
        searchBar.delegate = self
        searchBar.placeholder = "search.placeholder".localized
        searchBar.text = lastQuery.isEmpty ? nil : lastQuery
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            searchBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            searchBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            )
        ])
    }

    private func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier: SubscriptionVideoCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        // Heights come from `heightForRowAt`; the estimate keeps the table
        // asking only for visible rows instead of all of them on reload.
        tableView.estimatedRowHeight = 320
        tableView.separatorInset = UIEdgeInsets(
            top: 0, left: 12, bottom: 0, right: 12
        )
        tableView.translatesAutoresizingMaskIntoConstraints = false
        refreshControl.addTarget(
            self,
            action: #selector(handleRefresh),
            for: .valueChanged
        )
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        activateTableConstraints()
    }

    private func activateTableConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: searchBar.bottomAnchor
            ),
            tableView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            tableView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            tableView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        searchBar.barStyle = theme.barStyle
        searchBar.backgroundColor = theme.background
        searchBar.keyboardAppearance = theme.isDark ? .dark : .default
        tableView.reloadData()
    }

    @objc
    private func handleRefresh() {
        guard !lastQuery.isEmpty else {
            refreshControl.endRefreshing()
            return
        }
        search(query: lastQuery)
    }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text, !query.isEmpty else {
            return
        }
        searchBar.resignFirstResponder()
        search(query: query)
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        topBarHider.showBars()
        searchBar.setShowsCancelButton(true, animated: true)
        updatePanel(for: searchBar.text ?? "")
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
        showHistoryIfIdle()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        if searchText.isEmpty {
            clearSearchResults()
        }
        updatePanel(for: searchText)
    }
}
