import UIKit

/// A thin bar across the top of a video thumbnail while that video is being
/// saved. Like `DownloadBadgeView` it watches the download notifications
/// itself, so no screen has to know a download is running to show one.
final class DownloadProgressBar: UIView {
    static let height: CGFloat = 3

    private let fill = UIView()
    private var videoId: String?
    private var fraction: Double = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        fill.backgroundColor = ThemeManager.shared.accent
        addSubview(fill)
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        for name in [
            DownloadStore.didChangeNotification,
            VideoDownloader.didProgressNotification
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(refresh), name: name, object: nil
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func pin(toThumbnail thumbnail: UIView) {
        thumbnail.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: thumbnail.topAnchor),
            leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor),
            trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor),
            heightAnchor.constraint(equalToConstant: Self.height)
        ])
    }

    func configure(videoId: String?) {
        self.videoId = videoId
        refresh()
    }

    /// Frames rather than a constraint: the fill changes once a second and a
    /// width constraint would make the cell relayout each time.
    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width * CGFloat(fraction),
            height: bounds.height
        )
    }

    @objc
    private func refresh() {
        let downloader = VideoDownloader.shared
        guard let videoId, downloader.activeVideoId == videoId else {
            isHidden = true
            return
        }
        isHidden = false
        fraction = downloader.progress
        setNeedsLayout()
    }
}
