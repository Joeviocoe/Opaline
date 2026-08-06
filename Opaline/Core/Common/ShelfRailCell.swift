import UIKit

/// A horizontally scrolling shelf row ("rail") of video cards —
/// one rail per shelf section in the `.rails` home layout.
final class ShelfRailCell: UICollectionViewCell {
    static let reuseId = "ShelfRailCell"
    static let itemWidth: CGFloat = 280
    static var itemHeight: CGFloat { itemWidth * 9 / 16 + 92 }
    static var railHeight: CGFloat { itemHeight }

    var onVideoTap: ((Video) -> Void)?
    var onChannelTap: ((Video) -> Void)?
    var onMenuTap: ((Video, UIView) -> Void)?
    /// Fired when the rail scrolls near its trailing edge.
    var onNearEnd: (() -> Void)?

    private var videos: [Video] = []

    private lazy var listView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(
            width: Self.itemWidth,
            height: Self.itemHeight
        )
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: 8, bottom: 0, right: 8
        )
        let cv = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        cv.showsHorizontalScrollIndicator = false
        cv.backgroundColor = .clear
        cv.dataSource = self
        cv.delegate = self
        cv.register(
            VideoCell.self,
            forCellWithReuseIdentifier: VideoCell.reuseId
        )
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(listView)
        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: contentView.topAnchor),
            listView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            listView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with videos: [Video]) {
        // Rail cells get dequeued constantly during vertical scroll, and
        // reloading the inner collection on every reuse rebuilt the whole
        // horizontal row. Comparing every id is far cheaper than that, and
        // a reused cell still holds the previous shelf's list, so a partial
        // comparison could leave a stale row on screen.
        if self.videos.elementsEqual(videos, by: { $0.id == $1.id }) {
            return
        }
        self.videos = videos
        listView.reloadData()
        listView.setContentOffset(.zero, animated: false)
    }

    func appendVideos(_ newVideos: [Video]) {
        let start = videos.count
        videos.append(contentsOf: newVideos)
        let paths = (start..<videos.count).map {
            IndexPath(item: $0, section: 0)
        }
        listView.insertItems(at: paths)
    }
}

extension ShelfRailCell: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        videos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: VideoCell.reuseId,
            for: indexPath
        ) as? VideoCell else {
            return UICollectionViewCell()
        }
        let video = videos[indexPath.item]
        cell.forceGridLayout = true
        cell.configure(with: video)
        cell.onChannelTap = { [weak self] in
            self?.onChannelTap?(video)
        }
        cell.onMenuTap = { [weak self] anchor in
            self?.onMenuTap?(video, anchor)
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        onVideoTap?(videos[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        if indexPath.item >= videos.count - 3 {
            onNearEnd?()
        }
    }
}
