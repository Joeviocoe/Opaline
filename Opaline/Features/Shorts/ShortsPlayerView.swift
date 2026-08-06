import AVFoundation
import UIKit

/// The one AVPlayer the Shorts feed owns, moved between cells as the user
/// swipes. Deliberately minimal — a short needs playback, looping and a tap
/// to pause; everything the watch screen adds (quality menus, seek bar,
/// captions, PiP) is not part of this surface.
final class ShortsPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    let facade = PlaybackFacade()
    private let player = AVPlayer()
    private let statusLabel = UILabel()
    private var currentItem: AVPlayerItem?
    /// Retained for the item's lifetime — dropping it kills the stream.
    private var resourceLoader: AVAssetResourceLoaderDelegate?

    var isPaused: Bool { player.rate == 0 }

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Transparent so the cell's poster frame shows through until
        // the first decoded frame arrives.
        backgroundColor = .clear
        playerLayer?.player = player
        playerLayer?.videoGravity = .resizeAspect
        PlaybackBufferPolicy.configure(player: player)
        facade.context = self
        setupStatusLabel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Playback control

    func load(videoId: String, watchService: WatchService) {
        stop()
        facade.start(
            videoId: videoId,
            apiClient: watchService,
            cancellationToken: CancellationToken()
        )
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        resourceLoader = nil
        facade.reset()
        statusLabel.text = nil
    }

    func setPaused(_ paused: Bool) {
        if paused {
            player.pause()
        } else {
            player.play()
        }
    }

    @objc
    private func itemDidEnd() {
        player.seek(to: .zero)
        player.play()
    }

    private func setupStatusLabel() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor, constant: 16
            )
        ])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PlaybackContext

extension ShortsPlayerView: PlaybackContext {
    func attachPrepared(_ prepared: PreparedPlayback, resumeAt: CMTime?) {
        resourceLoader = prepared.resourceLoader
        currentItem = prepared.item
        PlaybackBufferPolicy.configure(item: prepared.item)
        player.replaceCurrentItem(with: prepared.item)
        statusLabel.text = nil
        player.play()
    }

    func updateStatusLabel(_ text: String) {
        statusLabel.text = text
    }

    func showPlaybackError(_ message: String) {
        statusLabel.text = message
    }

    func startObservingPlayerItem(_ item: AVPlayerItem) {}

    func stopObservingPlayerItem(_ item: AVPlayerItem) {}

    func setCaptionTracks(_ tracks: [SubtitleTrack]) {}
}
