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
    /// "Updated 10:52" / "Updating 5/17", tucked under the All button so it
    /// takes no row of its own and never sits where a tap is going.
    private let statusLabel = UILabel()
    private let separator = UIView()
    private var channels: [SubscribedChannel] = []
    private var selectedChannelId: String?
    private var newContentChannelIds: Set<String> = []
    private var refreshingChannelIds: Set<String> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A list with the same channels in the same order only re-applies
    /// state to the visible cells; a full reload re-dequeues every cell and
    /// re-resolves every avatar, which reads as the whole bar blinking.
    func setChannels(_ channels: [SubscribedChannel]) {
        let sameOrder = channels.map { $0.id } == self.channels.map { $0.id }
        self.channels = channels
        if sameOrder {
            reloadVisibleState()
        } else {
            collectionView.reloadData()
        }
    }

    func setSelectedChannelId(_ id: String?) {
        selectedChannelId = id
        reloadVisibleState()
    }

    func setNewContentChannelIds(_ ids: Set<String>) {
        newContentChannelIds = ids
        reloadVisibleState()
    }

    /// Channels whose uploads are being fetched right now; each spins an
    /// arc around its avatar. Kept here, not on the cell, so a reused or
    /// freshly dequeued cell picks the state up in `configure`.
    func setRefreshingChannelIds(_ ids: Set<String>) {
        guard ids != refreshingChannelIds else {
            return
        }
        refreshingChannelIds = ids
        reloadVisibleState()
    }

    func setStatus(_ text: String?) {
        statusLabel.text = text
        statusLabel.isHidden = (text ?? "").isEmpty
    }

    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        separator.backgroundColor = theme.separator
        allButton.tintColor = theme.accent
        statusLabel.textColor = theme.secondaryText
        for case let cell as ChannelAvatarCell in collectionView.visibleCells {
            cell.applyTheme()
        }
    }

    @objc
    private func allTapped() {
        onAllTapped?()
    }

    /// Re-applies selection / new-content / refreshing state to whatever
    /// cells are currently on screen, without a full reload (avatars/images
    /// stay put; only the derived state changes).
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
        applyState(to: cell, for: channel)
        cell.applyTheme()
    }

    private func applyState(
        to cell: ChannelAvatarCell, for channel: SubscribedChannel
    ) {
        cell.setSelected(channel.id == selectedChannelId)
        cell.setShowsNewContent(newContentChannelIds.contains(channel.id))
        cell.setRefreshing(refreshingChannelIds.contains(channel.id))
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

    /// The grid glyph on top, the two-line status under it, both centred on
    /// one column at the bar's right edge. The glyph is drawn, not a symbol:
    /// iOS 9 has no SF Symbols, and the app's other glyphs are drawn too.
    private func setupAllButton() {
        allButton.setImage(ChannelAvatarBarView.gridGlyph(), for: .normal)
        allButton.accessibilityLabel = "subscriptions.allButton".localized
        allButton.contentEdgeInsets = UIEdgeInsets(
            top: 8, left: 12, bottom: 8, right: 12
        )
        allButton.addTarget(
            self,
            action: #selector(allTapped),
            for: .touchUpInside
        )
        allButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(allButton)
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.isHidden = true
        statusLabel.isUserInteractionEnabled = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            allButton.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -4
            ),
            allButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            statusLabel.centerXAnchor.constraint(
                equalTo: allButton.centerXAnchor
            ),
            statusLabel.topAnchor.constraint(equalTo: allButton.bottomAnchor),
            // The status can be wider than the glyph, so the avatars stop
            // short of it as well.
            collectionView.trailingAnchor.constraint(
                lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -4
            )
        ])
    }

    /// Nine dots, three by three — "all of them". Template, so the button's
    /// tint colours it per theme.
    private static func gridGlyph() -> UIImage {
        let side: CGFloat = 22
        let dot: CGFloat = 5
        let gap = (side - dot * 3) / 2
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side)
        ).image { _ in
            UIColor.black.setFill()
            for row in 0..<3 {
                for column in 0..<3 {
                    UIBezierPath(ovalIn: CGRect(
                        x: CGFloat(column) * (dot + gap),
                        y: CGFloat(row) * (dot + gap),
                        width: dot, height: dot
                    )).fill()
                }
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
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
