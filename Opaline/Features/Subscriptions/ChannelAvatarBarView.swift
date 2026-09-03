import UIKit

/// Horizontal bar of circular channel avatars shown above the
/// Subscriptions feed, with an "All" button pinned to the right.
///
/// Backed by a `UICollectionView` (see `ShelfRailCell` for the same
/// horizontal-rail pattern elsewhere in the app) so only the visible
/// handful of avatars are ever instantiated — a subscriber with dozens
/// of channels no longer pays for building every avatar subtree up
/// front on first render.
final class ChannelAvatarBarView: UIView {
    static let preferredHeight: CGFloat = 88

    private static let cellReuseId = "ChannelAvatarCell"

    var onChannelTapped: ((SubscribedChannel) -> Void)?
    var onAllTapped: (() -> Void)?

    /// Setter stays private; the getter is read cross-file by the keyboard
    /// feature, which points a second `ListFocusController` at this same
    /// collection view rather than building a parallel focus mechanism for
    /// what is already exactly the shape `ListFocusController` handles.
    private(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(
            width: ChannelAvatarItemView.itemWidth,
            height: ChannelAvatarBarView.preferredHeight
        )
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: 12, bottom: 0, right: 12
        )
        let cv = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        cv.showsHorizontalScrollIndicator = false
        cv.backgroundColor = .clear
        // UIScrollView's clipsToBounds defaults to false, unlike a plain
        // UIView -- unset, a cell (or the keyboard focus ring, scrolled all
        // the way right) can render past this collection view's own
        // trailing edge and into the 4pt gap before the "All" button,
        // reading as the button overlapping the last channel.
        cv.clipsToBounds = true
        cv.dataSource = self
        cv.delegate = self
        cv.register(
            ChannelAvatarCell.self,
            forCellWithReuseIdentifier: ChannelAvatarBarView.cellReuseId
        )
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private let allButton = UIButton(type: .system)
    private let separator = UIView()
    private var channels: [SubscribedChannel] = []
    private var selectedChannelId: String?
    private var newContentChannelIds: Set<String> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setChannels(_ channels: [SubscribedChannel]) {
        self.channels = channels
        collectionView.reloadData()
    }

    func setSelectedChannelId(_ id: String?) {
        selectedChannelId = id
        reloadVisibleState()
    }

    func setNewContentChannelIds(_ ids: Set<String>) {
        newContentChannelIds = ids
        reloadVisibleState()
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        separator.backgroundColor = theme.separator
        allButton.setTitleColor(theme.accent, for: .normal)
        for case let cell as ChannelAvatarCell in collectionView.visibleCells {
            cell.applyTheme()
        }
    }

    @objc
    private func allTapped() {
        onAllTapped?()
    }

    /// Re-applies selection / new-content state to whatever cells are
    /// currently on screen, without a full reload (avatars/images stay
    /// put; only the derived state changes).
    private func reloadVisibleState() {
        for case let cell as ChannelAvatarCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else {
                continue
            }
            configure(cell, at: indexPath)
        }
    }

    private func configure(_ cell: ChannelAvatarCell, at indexPath: IndexPath) {
        guard indexPath.item < channels.count else {
            return
        }
        let channel = channels[indexPath.item]
        cell.configure(with: channel)
        cell.setSelected(channel.id == selectedChannelId)
        cell.setShowsNewContent(newContentChannelIds.contains(channel.id))
        cell.applyTheme()
    }

    private func setup() {
        addSubview(collectionView)
        setupAllButton()
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(
                equalTo: allButton.leadingAnchor,
                constant: -4
            ),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        applyTheme()
    }

    private func setupAllButton() {
        allButton.setTitle("subscriptions.allButton".localized, for: .normal)
        allButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        allButton.contentEdgeInsets = UIEdgeInsets(
            top: 8, left: 12, bottom: 8, right: 16
        )
        allButton.addTarget(
            self,
            action: #selector(allTapped),
            for: .touchUpInside
        )
        allButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(allButton)
        NSLayoutConstraint.activate([
            allButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            allButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

extension ChannelAvatarBarView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        channels.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChannelAvatarBarView.cellReuseId,
            for: indexPath
        ) as? ChannelAvatarCell else {
            return UICollectionViewCell()
        }
        configure(cell, at: indexPath)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard indexPath.item < channels.count else {
            return
        }
        onChannelTapped?(channels[indexPath.item])
    }
}

/// Reusable cell wrapping a single `ChannelAvatarItemView`. The item
/// view is created once per cell and rebound via `configure(with:)`
/// on reuse, exactly like `ShelfRailCell` reuses `VideoCell`.
