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
    private let progressBar = UIView()
    private var progressWidth: NSLayoutConstraint?
    private var timeObserver: Any?
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
        // Shorts fill the screen, as in the official app.
        playerLayer?.videoGravity = .resizeAspectFill
        PlaybackBufferPolicy.configure(player: player)
        facade.context = self
        setupStatusLabel()
        setupProgressBar()
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

    /// Plays an already-resolved short with no status label and no round
    /// trip. The facade is told what is playing so mid-playback recovery
    /// still has a video and a source to fall back on.
    func attach(
        source: VideoSource,
        playback: PreparedPlayback,
        videoId: String,
        watchService: WatchService
    ) {
        stop()
        facade.currentVideoId = videoId
        facade.currentApiClient = watchService
        facade.activeVideoSource = source
        attachPrepared(playback, resumeAt: nil)
    }

    func stop() {
        setProgress(0)
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

    /// The thin line along the bottom edge, as in the official app — no
    /// scrubbing, it only shows how far through the loop the short is.
    private func setupProgressBar() {
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.backgroundColor = ThemeManager.shared.accent
        addSubview(progressBar)
        let width = progressBar.widthAnchor.constraint(equalToConstant: 0)
        progressWidth = width
        NSLayoutConstraint.activate([
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
            width
        ])
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            self?.updateProgress(at: time)
        }
    }

    private func updateProgress(at time: CMTime) {
        guard let duration = player.currentItem?.duration,
              duration.isNumeric, duration.seconds > 0 else {
            setProgress(0)
            return
        }
        setProgress(time.seconds / duration.seconds)
    }

    private func setProgress(_ fraction: Double) {
        progressWidth?.constant = bounds.width
            * CGFloat(min(max(fraction, 0), 1))
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
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
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
