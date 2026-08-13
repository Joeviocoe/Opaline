import UIKit

// MARK: - Audio-only toggle
//
// The button doubles as the mode's indicator: hidden where the source has no
// separate audio stream (live, progressive), dimmed when the mode is off,
// accent-tinted when it is on. The mode carries across videos, and without a
// visible state that reads as the app having stopped showing video.

extension VideoPlayerView {
    func configureAudioOnlyButton() {
        // Same 26pt draw as the gear so the top bar reads as one row.
        audioOnlyButton.setImage(
            PlayerIcons.playerIcon("icon_audio_only", size: 26)
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        audioOnlyButton.accessibilityLabel = "player.quality.audioOnly".localized
        audioOnlyButton.translatesAutoresizingMaskIntoConstraints = false
        audioOnlyButton.addTarget(
            self,
            action: #selector(audioOnlyTapped),
            for: .touchUpInside
        )
        setAudioOnly(active: false, available: false)
        controlsView.addSubview(audioOnlyButton)
        NSLayoutConstraint.activate([
            audioOnlyButton.centerYAnchor.constraint(
                equalTo: settingsButton.centerYAnchor
            ),
            audioOnlyButton.trailingAnchor.constraint(
                equalTo: speedButton.leadingAnchor, constant: -4
            ),
            audioOnlyButton.widthAnchor.constraint(equalToConstant: 36),
            audioOnlyButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    /// Unavailable hides the button outright rather than greying it: a control
    /// that can never do anything for this video is noise, and the dimmed look
    /// is what "off" already means here.
    func setAudioOnly(active: Bool, available: Bool) {
        audioOnlyButton.isHidden = !available
        audioOnlyButton.tintColor = active ? ThemeManager.shared.accent : .white
        audioPlaceholderView.isHidden = !active
    }

    @objc
    private func audioOnlyTapped() {
        delegate?.videoPlayerViewDidTapAudioOnly(self)
    }

    /// Stands in for the empty player layer in audio-only mode. Deliberately
    /// not the video's thumbnail: a still frame looks like a stalled video,
    /// while this says which mode you are in.
    func setupAudioPlaceholder() {
        audioPlaceholderView.backgroundColor = .black
        audioPlaceholderView.isHidden = true
        audioPlaceholderView.isUserInteractionEnabled = false
        audioPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(audioPlaceholderView)
        let icon = UIImageView(
            image: UIImage(named: "icon_audio_only")?
                .withRenderingMode(.alwaysTemplate)
        )
        icon.tintColor = UIColor.white.withAlphaComponent(0.5)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        audioPlaceholderView.addSubview(icon)
        NSLayoutConstraint.activate([
            audioPlaceholderView.topAnchor.constraint(equalTo: topAnchor),
            audioPlaceholderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            audioPlaceholderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            audioPlaceholderView.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.centerXAnchor.constraint(
                equalTo: audioPlaceholderView.centerXAnchor
            ),
            icon.centerYAnchor.constraint(
                equalTo: audioPlaceholderView.centerYAnchor
            ),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}
