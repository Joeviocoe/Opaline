import UIKit

/// The comments sheet a short opens. A flat top-level list — replies and
/// sorting stay on the watch screen, where there is room for them.
final class ShortsCommentsViewController: UIViewController {
    private let videoId: String
    private let watchService: WatchService
    private let tableView = UITableView()
    private let titleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .gray)
    private var comments: [Comment] = []
    private var continuation: String?
    private var isLoading = false

    init(videoId: String, watchService: WatchService) {
        self.videoId = videoId
        self.watchService = watchService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        setupTable()
        applyTheme()
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading, comments.isEmpty || continuation != nil else {
            return
        }
        isLoading = true
        spinner.startAnimating()
        watchService.fetchComments(
            videoId: videoId,
            continuation: continuation,
            cancellationToken: nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handle(result)
            }
        }
    }

    private func handle(_ result: Result<CommentsPage, Error>) {
        isLoading = false
        spinner.stopAnimating()
        guard case .success(let page) = result else {
            AppLog.player("shorts comments failed")
            continuation = nil
            return
        }
        if let title = page.title {
            titleLabel.text = title
        }
        continuation = page.continuation
        comments.append(contentsOf: page.comments)
        tableView.reloadData()
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }

    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        titleLabel.textColor = theme.primaryText
        tableView.separatorColor = theme.separator
    }

    private func setupHeader() {
        titleLabel.text = "player.comments.title".localized
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        let close = UIButton(type: .system)
        close.setTitle("common.close".localized, for: .normal)
        close.addTarget(
            self, action: #selector(closeTapped), for: .touchUpInside
        )
        for subview in [titleLabel, close, spinner] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: guide.leadingAnchor, constant: 16
            ),
            titleLabel.topAnchor.constraint(
                equalTo: guide.topAnchor, constant: 16
            ),
            close.trailingAnchor.constraint(
                equalTo: guide.trailingAnchor, constant: -16
            ),
            close.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.register(CommentCell.self, forCellReuseIdentifier: CommentCell.reuseId)
        view.addSubview(tableView)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor, constant: 12
            ),
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - Table

extension ShortsCommentsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        comments.count
    }

    func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: CommentCell.reuseId, for: indexPath
        )
        (cell as? CommentCell)?.configure(
            comments[indexPath.row], linkDelegate: self
        )
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard indexPath.row >= comments.count - 3 else {
            return
        }
        loadNextPage()
    }
}

extension ShortsCommentsViewController: UITextViewDelegate {}
