import UIKit

/// The vertical swipe feed. Seeded with one short (tapped anywhere in the
/// app) and extended endlessly from `reel_watch_sequence`.
final class ShortsViewController: UIViewController {
    let shortsService: ShortsService
    let watchService: WatchService
    let engagementService: EngagementService
    private let channelViewControllerFactory: (String, String) -> UIViewController

    var videos: [Video]
    /// Continuation token, or the seed videoId params for the first page.
    var seed: String?
    var isLoading = false
    /// Index of the page the player is attached to.
    private var currentIndex = 0
    /// Videos whose metadata has been (or is being) fetched.
    var metadataFetched = Set<String>()
    /// Watch pages keyed by videoId — the source of the overlay's like count,
    /// like state and channel avatar.
    var pages: [String: WatchPage] = [:]
    /// Like state the user changed here, which outranks the fetched page.
    var likeOverrides: [String: LikeStatus] = [:]

    let playerView = ShortsPlayerView()
    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.isPagingEnabled = true
        view.showsVerticalScrollIndicator = false
        view.backgroundColor = .black
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()

    override var prefersStatusBarHidden: Bool { true }

    var attachedIndex: Int { currentIndex }

    init(
        seedVideos: [Video],
        shortsService: ShortsService,
        watchService: WatchService,
        engagementService: EngagementService,
        channelViewControllerFactory: @escaping (String, String) -> UIViewController
    ) {
        self.shortsService = shortsService
        self.watchService = watchService
        self.engagementService = engagementService
        self.channelViewControllerFactory = channelViewControllerFactory
        videos = seedVideos
        // When the seeded run is exhausted, YouTube's own sequence takes
        // over from the video the user actually picked.
        seed = seedVideos.first.map { ShortsSeed.params(videoId: $0.id) }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        // A seeded run (the channel Shorts tab) already has plenty to swipe
        // through — don't spend a request on the sequence until it thins out.
        if videos.count < 5 {
            loadNextPage()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The first page's cell only exists after layout — without this the
        // player has nothing to attach to and the seed short never starts.
        collectionView.layoutIfNeeded()
        attachPlayer(to: currentIndex)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerView.stop()
    }

    // MARK: - Paging

    /// Moves the single player into the page at `index` and starts it.
    func attachPlayer(to index: Int) {
        guard index >= 0, index < videos.count else {
            return
        }
        currentIndex = index
        let indexPath = IndexPath(item: index, section: 0)
        guard let cell = collectionView.cellForItem(
            at: indexPath
        ) as? ShortsCell else {
            return
        }
        movePlayer(into: cell.playerContainer)
        playerView.load(
            videoId: videos[index].id, watchService: watchService
        )
        fetchMetadata(for: index)
        if index >= videos.count - 3 {
            loadNextPage()
        }
    }

    private func movePlayer(into container: UIView) {
        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor
            ),
            playerView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            ),
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(
                equalTo: container.bottomAnchor
            )
        ])
    }

    func indexForCurrentOffset() -> Int {
        let height = collectionView.bounds.height
        guard height > 0 else {
            return currentIndex
        }
        return Int((collectionView.contentOffset.y / height).rounded())
    }

    func openChannel(for video: Video) {
        guard let channelId = video.channelId else {
            return
        }
        let channelVC = channelViewControllerFactory(
            channelId, video.channelName
        )
        navigationController?.pushViewController(channelVC, animated: true)
    }

    private func setupCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            ShortsCell.self,
            forCellWithReuseIdentifier: ShortsCell.reuseIdentifier
        )
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
