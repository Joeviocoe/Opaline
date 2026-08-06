import UIKit

// MARK: - Subtitle Display

extension VideoPlayerView {
    func setSubtitleCues(_ cues: [SubtitleCue]) {
        subtitleCues = cues
    }

    func clearSubtitles() {
        subtitleCues = []
        subtitleLabel.isHidden = true
        subtitleLabel.text = nil
        ccButton.isSelected = false
    }

    func updateSubtitle(at time: Double) {
        guard !subtitleCues.isEmpty else {
            if !subtitleLabel.isHidden {
                subtitleLabel.isHidden = true
            }
            return
        }
        let cue = activeCue(at: time)
        if let cue {
            if subtitleLabel.text != cue.text {
                subtitleLabel.text = cue.text
            }
            if subtitleLabel.isHidden {
                subtitleLabel.isHidden = false
            }
        } else {
            if !subtitleLabel.isHidden {
                subtitleLabel.isHidden = true
            }
        }
    }

    /// Cue covering `time`, or nil in a gap between cues.
    ///
    /// Cues are time-ordered, so this binary-searches for the last cue
    /// starting at or before `time`. A linear scan here cost ~1500
    /// comparisons per tick on a long video, ten times a second.
    private func activeCue(at time: Double) -> SubtitleCue? {
        var low = 0
        var high = subtitleCues.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if subtitleCues[mid].start <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard found >= 0, time < subtitleCues[found].end else {
            return nil
        }
        return subtitleCues[found]
    }

    func setCaptionTracks(
        _ tracks: [SubtitleTrack],
        activeLanguage: String?
    ) {
        setControlAvailability(ccButton, available: !tracks.isEmpty)
        ccButton.isSelected = activeLanguage != nil
    }

    @objc
    func ccTapped() {
        onCCTapped?()
    }
}
