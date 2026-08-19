import UIKit

/// The playing queue as a panel: the list the watch screen used to bury in
/// the related feed, with the queue's own controls in its header.
///
/// A collection view rather than a table, for `VideoCell` — its compact
/// horizontal layout (artwork left, two lines of text right) is the row the
/// official app uses for a queue, and it is already written.
///
/// Owns its list and is its own data source: the watch controller is already
/// the comments table's, and a type can only conform once.
final class QueuePanelController: NSObject {
    /// Artwork is 160pt wide at 16:9, and `VideoCell` picks its compact
    /// layout under 150pt of height.
    static let rowHeight: CGFloat = 110

    let sheet: PlayerSheetView

    /// A tapped row. The queue's cursor is not moved here: the watch screen
    /// navigates, and the page it loads syncs the cursor like any other jump.
    var onSelect: ((Video) -> Void)?
    var onShuffle: (() -> Void)?
    /// Repeat is the player's own loop toggle, surfaced here because the
    /// player hides its button while a queue is playing. The panel draws the
    /// state it is given and reports the tap.
    private(set) var isRepeating = false
    var onToggleRepeat: (() -> Void)?
    /// Raised as the list nears its end — the panel lists the queue, it does
    /// not know how the rest of it is fetched.
    var onLoadMore: (() -> Void)?
    var onMenu: ((Video, UIView) -> Void)?

    private let queue: PlaybackQueue
    private let listView: UICollectionView
    private let layout = UICollectionViewFlowLayout()
    private let shuffleButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)

    init(queue: PlaybackQueue) {
        self.queue = queue
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        listView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        sheet = PlayerSheetView(list: listView)
        super.init()
        setupList()
        setupButtons()
        sheet.isHidden = true
    }

    /// Repaints title, buttons and rows from the queue as it stands — called
    /// whenever the queue moves on, which on a mix is every video.
    func reload() {
        // "Mix – <what is playing>", the way the strip at the bottom of the
        // watch screen and the official app both name it.
        let name = queue.playlistTitle
            ?? "player.menu.queue".localized
        sheet.titleLabel.text = queue.currentVideo.map {
            "\(name) – \($0.title)"
        } ?? name
        applyRepeatState()
        listView.reloadData()
    }

    /// Repaints the one button, without the list reload `reload()` performs
    /// — a repeat tap must not scroll the list out from under a finger.
    func setRepeating(_ on: Bool) {
        isRepeating = on
        applyRepeatState()
    }

    func applyTheme(_ theme: ThemeManager) {
        sheet.applyTheme(theme)
        applyRepeatState()
    }

    /// Puts the playing row back in view — after a jump the list is often
    /// scrolled somewhere else entirely.
    func scrollToCurrent() {
        guard queue.currentIndex < listView.numberOfItems(inSection: 0) else {
            return
        }
        listView.scrollToItem(
            at: IndexPath(item: queue.currentIndex, section: 0),
            at: .top,
            animated: false
        )
    }

    private func setupList() {
        listView.register(
            VideoCell.self,
            forCellWithReuseIdentifier: VideoCell.reuseId
        )
        listView.dataSource = self
        listView.delegate = self
        listView.contentInsetAdjustmentBehavior = .never
        listView.alwaysBounceVertical = true
    }

    private func setupButtons() {
        // Template images, not the player's pre-filled white ones: the
        // repeat button says it is on by taking the accent tint.
        shuffleButton.setImage(
            resizedNavBarIcon("icon_shuffle", size: 22),
            for: .normal
        )
        shuffleButton.accessibilityLabel = "player.queue.shuffle".localized
        shuffleButton.addTarget(
            self,
            action: #selector(shuffleTapped),
            for: .touchUpInside
        )
        repeatButton.setImage(
            resizedNavBarIcon("icon_loop", size: 22),
            for: .normal
        )
        repeatButton.accessibilityLabel = "player.queue.repeat".localized
        repeatButton.addTarget(
            self,
            action: #selector(repeatTapped),
            for: .touchUpInside
        )
        for button in [repeatButton, shuffleButton] {
            button.addTapFeedback()
        }
        sheet.setHeaderButtons([repeatButton, shuffleButton])
    }

    @objc
    private func repeatTapped() {
        onToggleRepeat?()
    }

    @objc
    private func shuffleTapped() {
        onShuffle?()
    }

    private func applyRepeatState() {
        repeatButton.tintColor = isRepeating
            ? ThemeManager.shared.accent
            : ThemeManager.shared.primaryText
        shuffleButton.tintColor = queue.isShuffled
            ? ThemeManager.shared.accent
            : ThemeManager.shared.primaryText
    }
}

// MARK: - List

extension QueuePanelController: UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    )
        -> Int {
        queue.videos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    )
        -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: VideoCell.reuseId,
            for: indexPath
        )
        guard let videoCell = cell as? VideoCell,
              let video = queue.videos[safe: indexPath.item]
        else {
            return cell
        }
        videoCell.forceGridLayout = false
        videoCell.showsMixBadge = false
        videoCell.configure(with: video)
        // The playing row is marked by its background, as the official app
        // marks it — a badge would collide with the artwork.
        videoCell.contentView.backgroundColor = indexPath.item == queue.currentIndex
            ? ThemeManager.shared.primaryText.withAlphaComponent(0.14)
            : .clear
        videoCell.onMenuTap = { [weak self] anchor in
            self?.onMenu?(video, anchor)
        }
        return videoCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    )
        -> CGSize {
        CGSize(
            width: collectionView.bounds.width,
            height: Self.rowHeight
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if indexPath.item >= queue.videos.count - 4 {
            onLoadMore?()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let video = queue.videos[safe: indexPath.item],
              indexPath.item != queue.currentIndex
        else {
            return
        }
        onSelect?(video)
    }
}
