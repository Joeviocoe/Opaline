import UIKit

// MARK: - Subtitle Handling

extension WatchViewController {
    func showSubtitlePicker() {
        var items: [PlayerMenuItem] = []
        if activeSubtitleLanguage != nil {
            items.append(
                PlayerMenuItem(
                    title: "player.subtitles.off".localized,
                    isDestructive: true
                ) { [weak self] in
                    self?.deactivateSubtitles()
                }
            )
        }
        for track in captionTracks {
            let suffix = track.isAsr
                ? "player.subtitles.autoSuffix".localized : ""
            items.append(
                PlayerMenuItem(title: track.name + suffix) { [weak self] in
                    self?.activateSubtitle(track: track)
                }
            )
        }
        presentPlayerMenu(
            title: "player.menu.subtitles".localized, items: items
        )
    }

    func activateSubtitle(track: SubtitleTrack) {
        activeSubtitleLanguage = track.languageCode
        videoPlayerView?.setCaptionTracks(
            captionTracks,
            activeLanguage: track.languageCode
        )
        SubtitleService.shared.load(
            track: track
        ) { [weak self] cues in
            self?.videoPlayerView?.setSubtitleCues(cues)
        }
    }

    func deactivateSubtitles() {
        activeSubtitleLanguage = nil
        videoPlayerView?.clearSubtitles()
        videoPlayerView?.setCaptionTracks(
            captionTracks,
            activeLanguage: nil
        )
    }
}
