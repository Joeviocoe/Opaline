import UIKit

/// The download marker in the corner of a video thumbnail: solid once the
/// video is saved, pulsing while it is being saved, red when the job failed.
///
/// It watches the download notifications itself rather than making every
/// screen refresh its cells — a badge is the only thing on a row that has to
/// react to a job on the other side of the app.
final class DownloadBadgeView: UIImageView {
    static let size: CGFloat = 18

    private var videoId: String?

    init() {
        super.init(image: LegacyAssets.image("icon_download")?
            .withRenderingMode(.alwaysTemplate))
        contentMode = .scaleAspectFit
        tintColor = .white
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 2
        layer.shadowOffset = .zero
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

    /// Corner placement is the same wherever it goes, so the cells do not each
    /// carry a copy of it.
    func pin(toThumbnail thumbnail: UIView) {
        thumbnail.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 6),
            trailingAnchor.constraint(
                equalTo: thumbnail.trailingAnchor, constant: -6
            ),
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size)
        ])
    }

    func configure(videoId: String?) {
        self.videoId = videoId
        refresh()
    }

    @objc
    private func refresh() {
        guard let videoId = videoId else {
            apply(.none)
            return
        }
        apply(DownloadStatus.of(videoId))
    }

    /// The same colours the player uses: accent means the video is here,
    /// plain white means it is on its way, yellow means it stopped and wants
    /// a decision.
    private func apply(_ status: DownloadStatus) {
        isHidden = status == .none
        switch status {
        case .ready:
            tintColor = ThemeManager.shared.accent
        case .failed:
            tintColor = .systemYellow
        default:
            tintColor = .white
        }
        if status.isActive {
            startPulsing()
        } else {
            layer.removeAnimation(forKey: "pulse")
            alpha = 1
        }
    }

    /// Fades rather than scales: a scaling badge in the corner of a scrolling
    /// list reads as jitter, and this has to survive on an A7.
    private func startPulsing() {
        guard layer.animation(forKey: "pulse") == nil else {
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "pulse")
    }
}
