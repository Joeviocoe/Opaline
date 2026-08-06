import UIKit

// MARK: - Audio-track (dub) picker
//
// Fully source-driven, like the quality picker: the active `VideoSource` owns
// its audio tracks and how switching works. No source-specific logic here.

extension WatchViewController {
    func showAudioTrackPicker() {
        guard let source = playbackFacade.activeVideoSource,
              source.supportsAudioTrackSelection else {
            return
        }
        let items = source.availableAudioTracks.map { track -> PlayerMenuItem in
            let isCurrent = track == source.currentAudioTrack
            let name = track.isAutoDubbed
                ? track.displayName + "player.audioTrack.aiSuffix".localized
                : track.displayName
            let title = isCurrent ? "✓ \(name)" : name
            return PlayerMenuItem(title: title) { [weak self] in
                self?.selectAudioTrack(track, source: source)
            }
        }
        presentPlayerMenu(
            title: "player.menu.audioTrack".localized, items: items
        )
    }

    /// Auto-dub: tracks discovered by the composite's background probe after
    /// playback started. If the preference picks a dub, switch to it through
    /// the same path a manual pick uses.
    @objc
    func audioTracksDidChange(_ note: Notification) {
        guard let source = playbackFacade.activeVideoSource,
              note.object as? VideoSource === source,
              let target = AutoDubPreference.autoDubTrack(
                  in: source.availableAudioTracks
              ),
              target != source.currentAudioTrack else {
            return
        }
        AppLog.player("autoDub: switching to \(target.id)")
        selectAudioTrack(target, source: source)
    }

    private func selectAudioTrack(
        _ track: AudioTrack,
        source: VideoSource
    ) {
        guard track != source.currentAudioTrack else {
            return
        }
        let resumeTime = videoPlayerView?.player?.currentTime()
        playerStatusLabel.text = "player.status.loading"
            .localized(with: track.displayName)
        playerStatusLabel.isHidden = false
        source.selectAudioTrack(track) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let prepared):
                    self?.attachPrepared(prepared, resumeAt: resumeTime)
                case .failure:
                    self?.showPlaybackError(
                        "player.error.audioTrackSwitch".localized
                    )
                }
            }
        }
    }
}
