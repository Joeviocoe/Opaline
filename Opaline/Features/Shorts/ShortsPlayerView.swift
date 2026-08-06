import AVFoundation
import UIKit

/// The one player the Shorts feed owns, moved between cells as the user
/// swipes. Deliberately minimal — a short needs playback, looping and a tap
/// to pause; everything the watch screen adds (quality menus, seek bar,
/// captions, PiP) is not part of this surface.
///
/// An `AVQueuePlayer` so the next short can be queued behind the current one
/// and pre-rolled by the same player. Handing a prepared item from a second
/// player is not an option: AVFoundation detaches asynchronously and the
/// attach throws (crashed on device, see [[ShortsPrefetcher]]).
/// `actionAtItemEnd` is `.pause` — a queued short must not start on its own,
/// shorts loop until the user swipes.
final class ShortsPlayerView: UIView {
    /// One queued short. The source and resource loader are retained for as
    /// long as the item is in the queue — dropping either kills the stream.
    struct Entry {
        let videoId: String
        let item: AVPlayerItem
        let source: VideoSource?
        let loader: AVAssetResourceLoaderDelegate?
    }

    override static var layerClass: AnyClass { AVPlayerLayer.self }

    let facade = PlaybackFacade()
    private let player = AVQueuePlayer()
    private let statusLabel = UILabel()
    private let progressBar = UIView()
    private var progressWidth: NSLayoutConstraint?
    private var timeObserver: Any?
    /// Mirrors the player's queue: index 0 is playing, 1 is pre-rolling.
    private var entries: [Entry] = []

    var isPaused: Bool { player.rate == 0 }

    /// The short already queued behind the current one, if any.
    var queuedVideoId: String? {
        entries.count > 1 ? entries[1].videoId : nil
    }

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
        player.actionAtItemEnd = .pause
        facade.context = self
        setupStatusLabel()
        setupProgressBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidEnd(_:)),
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
        play(entry: Entry(
            videoId: videoId,
            item: playback.item,
            source: source,
            loader: playback.resourceLoader
        ))
    }

    /// Queues a resolved short behind the current one so the player pre-rolls
    /// it. Only one is ever queued — that is the one swipe ahead.
    func enqueue(
        source: VideoSource,
        playback: PreparedPlayback,
        videoId: String
    ) {
        guard !entries.isEmpty, entries.count < 2,
              entries[0].videoId != videoId,
              player.canInsert(playback.item, after: nil) else {
            return
        }
        PlaybackBufferPolicy.configure(item: playback.item)
        player.insert(playback.item, after: nil)
        entries.append(Entry(
            videoId: videoId,
            item: playback.item,
            source: source,
            loader: playback.resourceLoader
        ))
    }

    /// Jumps to the queued short. Returns false when `videoId` is not the one
    /// queued — a backward or skipping swipe, which has to resolve normally.
    func advance(to videoId: String, watchService: WatchService) -> Bool {
        guard queuedVideoId == videoId else {
            return false
        }
        player.advanceToNextItem()
        entries.removeFirst()
        facade.currentVideoId = videoId
        facade.currentApiClient = watchService
        facade.activeVideoSource = entries[0].source
        statusLabel.text = nil
        setProgress(0)
        player.play()
        return true
    }

    private func play(entry: Entry) {
        PlaybackBufferPolicy.configure(item: entry.item)
        player.removeAllItems()
        player.insert(entry.item, after: nil)
        entries = [entry]
        statusLabel.text = nil
        player.play()
    }

    func stop() {
        setProgress(0)
        player.pause()
        player.removeAllItems()
        entries = []
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
    private func itemDidEnd(_ note: Notification) {
        guard (note.object as? AVPlayerItem) === player.currentItem else {
            return
        }
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
        play(entry: Entry(
            videoId: facade.currentVideoId ?? "",
            item: prepared.item,
            source: facade.activeVideoSource,
            loader: prepared.resourceLoader
        ))
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
