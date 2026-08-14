import AVFoundation
import UIKit

// MARK: - Source-prepared playback

extension WatchViewController {
    /// Attaches an `AVPlayerItem` built by a `VideoSource`, retaining its
    /// resource loader (e.g. the HLS proxy) for the item's lifetime and
    /// publishing any caption tracks the source resolved.
    func attachPrepared(
        _ prepared: PreparedPlayback,
        resumeAt: CMTime? = nil
    ) {
        activeResourceLoader = prepared.resourceLoader
        if !prepared.captions.isEmpty {
            setCaptionTracks(prepared.captions)
        }
        // After `attachPlayer` — it is what creates the player view on a
        // first load, so an earlier call would land on nothing.
        attachPlayer(item: prepared.item)
        videoPlayerView?.setAudioOnly(
            active: AudioOnlyMode.isEnabled,
            available: playbackFacade.activeVideoSource?.availableQualities
                .contains { $0.id == AudioOnlyMode.qualityID } ?? false
        )
        if let resumeAt, CMTimeGetSeconds(resumeAt) > 1 {
            pendingResumeSeek = resumeAt
        }
    }

    /// Seeks a freshly attached stream back to where the user was. Called from
    /// the item's ready callback: issued any earlier the player is still
    /// loading and silently drops it.
    func applyResumeSeekIfNeeded() {
        guard let target = pendingResumeSeek else {
            return
        }
        pendingResumeSeek = nil
        let tolerance = CMTime(seconds: 1, preferredTimescale: 1_000)
        videoPlayerView?.player?.seek(
            to: target,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        )
    }

    /// Source-agnostic quality menu: renders `source.availableQualities` and
    /// applies the pick via `source.selectQuality`. No source-specific code.
    func showSourceQualityPicker(source: VideoSource) {
        let items = source.availableQualities.map { quality -> PlayerMenuItem in
            let isCurrent = quality == source.currentQuality
            let title = isCurrent ? "✓ \(quality.label)" : quality.label
            return PlayerMenuItem(title: title) { [weak self] in
                self?.selectSourceQuality(quality, source: source)
            }
        }
        presentPlayerMenu(
            title: "player.menu.quality".localized, items: items
        )
    }

    func selectSourceQuality(
        _ quality: VideoQuality,
        source: VideoSource
    ) {
        guard quality != source.currentQuality else {
            return
        }
        let resumeTime = videoPlayerView?.player?.currentTime()
        playerStatusLabel.text = "player.status.loading"
            .localized(with: quality.label)
        playerStatusLabel.isHidden = false
        source.selectQuality(
            quality, resumeAt: resumeTime.map(CMTimeGetSeconds)
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let prepared):
                    self?.attachPrepared(prepared, resumeAt: resumeTime)
                case .failure:
                    self?.showPlaybackError(
                        "player.error.qualitySwitch".localized
                    )
                }
            }
        }
    }
}
