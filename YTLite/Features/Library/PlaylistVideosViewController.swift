import UIKit

final class PlaylistVideosViewController: UIViewController {
    static let skeletonCount = 6

    let playlist: Playlist
    private let service: PlaylistService
    let channelViewControllerFactory: (
        String,
        String
    ) -> UIViewController
    let videoRouter: VideoRouter
    var videos: [Video] = []
    var isLoading = true
    private var continuationToken: String?
    private var isLoadingMore = false
    let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .white)
    private let emptyLabel = UILabel()
    private lazy var topBarHider = TopBarAutoHider(owner: self)

    init(
        playlist: Playlist,
        service: PlaylistService,
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> UIViewController,
        videoRouter: VideoRouter = .shared
    ) {
        self.playlist = playlist
        self.service = service
        self.channelViewControllerFactory = channelViewControllerFactory
        self.videoRouter = videoRouter
        super.init(nibName: nil, bundle: nil)
        title = playlist.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupSpinner()
        setupEmpty()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        loadVideos()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        topBarHider.showBars()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }
        topBarHider.handleScroll(scrollView)
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier: SubscriptionVideoCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        // rowHeight = 220 only fits the iPad wide layout; on iPhone the cell uses a
        // stacked layout whose height depends on the thumbnail aspect ratio.
        // Use automaticDimension + a generous estimate so cells size themselves.
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 320
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refresh
    }

    private func setupSpinner() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
    }

    private func setupEmpty() {
        emptyLabel.textColor = .lightGray
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - Theme

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        if let rc = tableView.refreshControl {
            rc.tintColor = theme.secondaryText
        }
        tableView.reloadData()
    }

    // MARK: - Data

    private func applyLoadResult(
        _ result: Result<FeedPage, Error>
    ) {
        switch result {
        case .success(let page):
            videos = page.videos
            continuationToken = page.continuation
            emptyLabel.isHidden = !page.videos.isEmpty
            if page.videos.isEmpty {
                emptyLabel.text = "library.playlist.empty".localized
            }
        case .failure(let error):
            AppLog.log("Playlist", "load error: \(error)")
            emptyLabel.text = "library.playlist.loadFailed".localized
            emptyLabel.isHidden = false
        }
        tableView.reloadData()
    }

    private func loadVideos() {
        isLoading = true
        continuationToken = nil
        service.fetchPlaylistVideos(
            playlistId: playlist.id,
            continuation: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isLoading = false
                self.spinner.stopAnimating()
                self.tableView.refreshControl?.endRefreshing()
                self.applyLoadResult(result)
            }
        }
    }

    /// Appends the next 15-video page once scrolling nears the end.
    func loadMoreVideos() {
        guard let token = continuationToken,
              !isLoadingMore, !isLoading else {
            return
        }
        isLoadingMore = true
        service.fetchPlaylistVideos(
            playlistId: playlist.id,
            continuation: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isLoadingMore = false
                guard case .success(let page) = result else {
                    return
                }
                self.continuationToken = page.continuation
                self.videos += page.videos
                self.tableView.reloadData()
            }
        }
    }

    @objc
    private func handleRefresh() {
        loadVideos()
    }

    /// The network removal round trip finishes after this view's `videos`
    /// may have changed further, so look the video up by id rather than
    /// trusting a captured index path.
    func removeVideoFromList(videoId: String) {
        guard let index = videos.firstIndex(where: { $0.id == videoId }) else {
            return
        }
        videos.remove(at: index)
        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        if videos.isEmpty {
            emptyLabel.text = "library.playlist.empty".localized
            emptyLabel.isHidden = false
        }
    }
}
