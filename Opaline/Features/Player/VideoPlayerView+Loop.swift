import UIKit

// MARK: - Loop toggle
//
// Sits in the top control row next to speed / CC / PiP so repeating a video
// costs one tap. The button is its own indicator: accent-tinted when on,
// white when off, like the audio-only toggle. The end-of-item handler in
// `WatchViewController+PlayerObserving` reads `isLooping`, so the restart
// also happens with the app backgrounded or in PiP.

extension VideoPlayerView {
    func configureLoopButton() {
        loopButton.setImage(
            PlayerIcons.playerIcon("icon_loop", size: 26)
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        loopButton.accessibilityLabel = "player.loop".localized
        loopButton.translatesAutoresizingMaskIntoConstraints = false
        loopButton.addTarget(
            self,
            action: #selector(loopTapped),
            for: .touchUpInside
        )
        updateLoopButton()
        controlsView.addSubview(loopButton)
        NSLayoutConstraint.activate([
            loopButton.centerYAnchor.constraint(
                equalTo: settingsButton.centerYAnchor
            ),
            loopButton.trailingAnchor.constraint(
                equalTo: audioOnlyButton.leadingAnchor, constant: -4
            ),
            loopButton.widthAnchor.constraint(equalToConstant: 36),
            loopButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    func updateLoopButton() {
        loopButton.tintColor = isLooping
            ? ThemeManager.shared.accent
            : .white
    }

    @objc
    private func loopTapped() {
        isLooping.toggle()
        AppLog.player("loop toggled: \(isLooping)")
        scheduleAutoHide()
    }
}
