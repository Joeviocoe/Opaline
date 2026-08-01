import AVFoundation
import UIKit

// MARK: - Stream URL Expiration Recovery

extension WatchViewController {
    func recoverPlayback() {
        guard !isRecoveringPlayback,
              let player = videoPlayerView?.player
        else {
            return
        }
        let position = player.currentTime().seconds
        let wasPlaying = player.rate > 0
        AppLog.player(
            "recoverPlayback: pos=\(position)s"
                + " wasPlaying=\(wasPlaying)"
        )
        let token = CancellationToken()
        pageLoadToken = token
        guard playbackFacade.recover(cancellationToken: token) else {
            showPlaybackError("player.error.playback".localized)
            return
        }
        isRecoveringPlayback = true
        hasSeenPlaybackError = false
        recoveryTargetSeconds = position
    }

    func applyRecoverySeekIfNeeded(
        _ item: AVPlayerItem
    ) -> Bool {
        guard let target = recoveryTargetSeconds else {
            return false
        }
        recoveryTargetSeconds = nil
        isRecoveringPlayback = false
        let duration = CMTimeGetSeconds(item.duration)
        AppLog.player(
            "recoverPlayback: ready"
                + " duration=\(duration)s"
                + " seekTo=\(target)s"
        )
        let time = CMTime(
            seconds: target,
            preferredTimescale: 1_000
        )
        videoPlayerView?.player?.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.videoPlayerView?.player?.play()
        }
        return true
    }
}
