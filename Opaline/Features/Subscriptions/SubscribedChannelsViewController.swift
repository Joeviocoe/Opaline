import UIKit

/// Full list of the user's subscribed channels,
/// opened from the "All" button in the channel avatar bar.
final class SubscribedChannelsViewController: UIViewController {
    private let channels: [SubscribedChannel]
    private let newContentChannelIds: Set<String>
    private let channelViewControllerFactory: (
        String,
        String
    ) -> UIViewController
    private let tableView = UITableView()
    private lazy var topBarHider = TopBarAutoHider(owner: self)

    init(
        channels: [SubscribedChannel],
        newContentChannelIds: Set<String> = [],
        channelViewControllerFactory: @escaping (
            String,
            String
        ) -> UIViewController
    ) {
        self.channels = channels
        self.newContentChannelIds = newContentChannelIds
        self.channelViewControllerFactory = channelViewControllerFactory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "subscriptions.all".localized
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
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

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        tableView.reloadData()
    }

    private func setupTableView() {
        tableView.register(
            SubscribedChannelCell.self,
            forCellReuseIdentifier: SubscribedChannelCell.reuseId
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension SubscribedChannelsViewController: UITableViewDataSource {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        channels.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SubscribedChannelCell.reuseId,
            for: indexPath
        ) as? SubscribedChannelCell else {
            return UITableViewCell()
        }
        let channel = channels[indexPath.row]
        cell.configure(
            with: channel,
            showsNewContentDot: newContentChannelIds.contains(channel.id)
        )
        return cell
    }
}

extension SubscribedChannelsViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = channels[indexPath.row]
        navigationController?.pushViewController(
            channelViewControllerFactory(channel.id, channel.title),
            animated: true
        )
    }
}

// MARK: - Cell

private final class SubscribedChannelCell: UITableViewCell {
    static let reuseId = "SubscribedChannelCell"

    private let avatarView = ChannelAvatarView()
    private let nameLabel = UILabel()
    private let dotView = NewContentDotView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.reset()
        nameLabel.text = nil
        dotView.isHidden = true
    }

    func configure(
        with channel: SubscribedChannel,
        showsNewContentDot: Bool
    ) {
        avatarView.configure(with: channel)
        nameLabel.text = channel.title
        dotView.isHidden = !showsNewContentDot
        applyTheme()
    }

    private func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        nameLabel.textColor = theme.primaryText
        avatarView.applyTheme()
        dotView.applyTheme()
    }

    private func setupLayout() {
        selectionStyle = .none
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(dotView)
        dotView.constrainToTopRight(of: avatarView)
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 16
            ),
            avatarView.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor
            ),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),
            nameLabel.leadingAnchor.constraint(
                equalTo: avatarView.trailingAnchor,
                constant: 14
            ),
            nameLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -16
            ),
            nameLabel.centerYAnchor.constraint(
                equalTo: contentView.centerYAnchor
            )
        ])
    }
}
