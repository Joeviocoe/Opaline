import AVFoundation
import MediaPlayer
import UIKit

/// What a playback session shows on the lock screen / Control Center.
struct NowPlayingMetadata {
    let title: String
    let channelName: String
    let duration: TimeInterval
    let artworkURL: URL?
}

/// Manages Now Playing info and remote command handling (Control Center, AirPods, lock screen).
final class NowPlayingService {
    static let shared = NowPlayingService()

    private weak var player: AVPlayer?
    private var onNextTrack: (() -> Void)?
    private var onPreviousTrack: (() -> Void)?
    private var onRemotePause: (() -> Void)?
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var artworkURL: URL?
    private var lastPublishedPosition: TimeInterval = -1
    private let transport: HTTPTransport

    private init(transport: HTTPTransport = ServiceContainer.mediaTransport) {
        self.transport = transport
    }

    func beginSession(
        player: AVPlayer,
        metadata: NowPlayingMetadata,
        onNext: (() -> Void)? = nil,
        onPrevious: (() -> Void)? = nil,
        onPause: (() -> Void)? = nil
    ) {
        self.player = player
        onNextTrack = onNext
        onPreviousTrack = onPrevious
        onRemotePause = onPause
        lastPublishedPosition = 0
        publishInfo(metadata: metadata, position: 0)
        registerCommands()
        loadArtwork(url: metadata.artworkURL)
    }

    /// Re-points the session at a replacement player for the same item.
    func rebindPlayer(_ player: AVPlayer) {
        self.player = player
    }

    func updatePosition(_ position: TimeInterval) {
        // The lock screen advances elapsed time by itself from playbackRate;
        // rewriting the info dict on every 0.1s tick kept iOS 12 from ever
        // rendering the artwork. Republish only on seeks or notable drift.
        guard abs(position - lastPublishedPosition) >= 5 else {
            return
        }
        lastPublishedPosition = position
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func endSession() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        removeCommands()
        player = nil
        onNextTrack = nil
        onPreviousTrack = nil
        onRemotePause = nil
        artworkURL = nil
    }

    // MARK: - Private

    private func publishInfo(
        metadata: NowPlayingMetadata,
        position: TimeInterval
    ) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.channelName,
            MPMediaItemPropertyPlaybackDuration: metadata.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: player?.rate ?? 1,
            MPNowPlayingInfoPropertyMediaType:
                MPNowPlayingInfoMediaType.video.rawValue
        ]
    }

    private func loadArtwork(url: URL?) {
        artworkURL = url
        guard let url = url else {
            return
        }
        transport.send(
            HTTPRequest(method: .get, url: url),
            cancellationToken: nil
        ) { [weak self] result in
            guard let data = try? result.get().data,
                  let image = UIImage(data: data) else {
                return
            }
            DispatchQueue.main.async {
                self?.publishArtwork(image, for: url)
            }
        }
    }

    private func publishArtwork(_ image: UIImage, for url: URL) {
        // The session may have moved to another video while downloading.
        guard url == artworkURL,
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
            boundsSize: image.size
        ) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func registerCommands() {
        removeCommands()
        let center = MPRemoteCommandCenter.shared()
        registerPlayPauseCommands(center)
        registerSeekCommand(center)
        registerTrackCommands(center)
    }

    /// Next/previous (Control Center, lock screen, AirPods). Commands with
    /// no handler stay disabled so the buttons render greyed out.
    private func registerTrackCommands(
        _ center: MPRemoteCommandCenter
    ) {
        if onNextTrack != nil {
            add(center.nextTrackCommand) { [weak self] _ in
                self?.onNextTrack?()
                return .success
            }
        } else {
            center.nextTrackCommand.isEnabled = false
        }
        if onPreviousTrack != nil {
            add(center.previousTrackCommand) { [weak self] _ in
                self?.onPreviousTrack?()
                return .success
            }
        } else {
            center.previousTrackCommand.isEnabled = false
        }
    }

    private func registerPlayPauseCommands(
        _ center: MPRemoteCommandCenter
    ) {
        add(center.playCommand) { [weak self] _ in
            self?.player?.play()
            return .success
        }
        add(center.pauseCommand) { [weak self] _ in
            self?.pauseFromRemote()
            return .success
        }
        add(center.togglePlayPauseCommand) { [weak self] _ in
            guard let player = self?.player else {
                return .commandFailed
            }
            if player.rate > 0 { self?.pauseFromRemote() } else { player.play() }
            return .success
        }
    }

    /// A remote pause is as deliberate as tapping our own pause button, so the
    /// session announces it. Without that, the player reads it as a pause it
    /// did not ask for and plays again half a second later.
    private func pauseFromRemote() {
        onRemotePause?()
        player?.pause()
    }

    private func registerSeekCommand(
        _ center: MPRemoteCommandCenter
    ) {
        add(center.changePlaybackPositionCommand) { [weak self] event in
            guard let ev = event as? MPChangePlaybackPositionCommandEvent,
                  let player = self?.player
            else {
                return .commandFailed
            }
            let target = CMTime(
                seconds: ev.positionTime,
                preferredTimescale: 1_000
            )
            player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            return .success
        }
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let token = command.addTarget(handler: handler)
        commandTokens.append((command, token))
    }

    private func removeCommands() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
            command.isEnabled = false
        }
        commandTokens = []
    }
}
