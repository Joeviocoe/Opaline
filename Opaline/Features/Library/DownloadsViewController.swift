import UIKit

/// Saved videos, read straight off the filesystem. No service, no paging and
/// no sign-in: a folder either holds a playable file or it does not.
final class DownloadsViewController: UIViewController {
    private let channelViewControllerFactory: (String, String) -> UIViewController
    private let videoRouter: VideoRouter
    private(set) var videos: [Video] = []
    private let tableView = UITableView()
    private let emptyLabel = UILabel()
    private lazy var topBarHider = TopBarAutoHider(owner: self)

    init(
        channelViewControllerFactory: @escaping (String, String) -> UIViewController,
        videoRouter: VideoRouter = .shared
    ) {
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
        title = "library.downloads".localized
        setupTableView()
        setupEmpty()
        applyTheme()
        // Not the progress notification: the badge and the bar on each card
        // repaint themselves once a second, and reloading the table at that
        // rate made the whole screen blink.
        for name in [
            ThemeManager.didChangeNotification,
            DownloadStore.didChangeNotification
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reload), name: name, object: nil
            )
        }
        reload()
    }

    /// Cheap enough to redo on every appearance: a handful of small files.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        topBarHider.showBars()
    }

    @objc
    func reload() {
        let fresh = DownloadStore.downloads()
        emptyLabel.isHidden = !fresh.isEmpty
        // A reload swaps every visible thumbnail out and back in, which reads
        // as a flash. The rows only change when a download is added or
        // removed; the state inside them repaints itself.
        guard fresh.map(\.id) != videos.map(\.id) else {
            videos = fresh
            return
        }
        videos = fresh
        // The thumbnails outlive the image cache, which expires and can be
        // purged; hand them back to it before the cells ask.
        videos.forEach(DownloadStore.primeThumbnail)
        tableView.reloadData()
    }

    func openChannel(for video: Video) {
        guard let channelId = video.channelId else {
            return
        }
        let targetNav = navigationController?.parent?
            .navigationController ?? navigationController
        targetNav?.pushViewController(
            channelViewControllerFactory(channelId, video.channelName),
            animated: true
        )
    }

    func open(_ video: Video) {
        videoRouter.open(video: video, from: self)
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.register(
            SubscriptionVideoCell.self,
            forCellReuseIdentifier: SubscriptionVideoCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 220
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmpty() {
        emptyLabel.text = "library.downloads.empty".localized
        emptyLabel.textColor = .lightGray
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 32
            ),
            emptyLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -32
            )
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        tableView.reloadData()
    }
}
