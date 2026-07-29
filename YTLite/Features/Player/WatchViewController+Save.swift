import UIKit

// MARK: - Save to playlist

extension WatchViewController {
    /// Fetched when the watch page loads so the sheet opens without a wait.
    func prefetchPlaylistOptions() {
        let videoId = watchPage?.video.id ?? initialVideo.id
        playlistClient.fetchAddToPlaylistOptions(
            videoId: videoId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard case .success(let options) = result else {
                    return
                }
                self?.playlistOptions = options
                self?.updateSaveButton()
            }
        }
    }

    @objc
    func saveTapped() {
        if let options = playlistOptions {
            presentPlaylistPicker(options)
            return
        }
        saveButton.isEnabled = false
        let videoId = watchPage?.video.id ?? initialVideo.id
        playlistClient.fetchAddToPlaylistOptions(
            videoId: videoId
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.saveButton.isEnabled = true
                switch result {
                case .success(let options):
                    self?.playlistOptions = options
                    self?.updateSaveButton()
                    self?.presentPlaylistPicker(options)
                case .failure(let error):
                    AppLog.player("playlist options failed: \(error)")
                    self?.showSaveError()
                }
            }
        }
    }

    /// Accent when the video sits in at least one playlist.
    func updateSaveButton() {
        let saved = playlistOptions?.contains { $0.isAdded } == true
        saveButton.tintColor = saved
            ? ThemeManager.shared.accent
            : ThemeManager.shared.primaryText
    }

    private func presentPlaylistPicker(
        _ options: [PlaylistAddOption]
    ) {
        let sheet = UIAlertController(
            title: "player.action.saveTo".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        for option in options {
            sheet.addAction(UIAlertAction(
                title: option.isAdded
                    ? "✓ \(option.title)"
                    : option.title,
                style: .default
            ) { [weak self] _ in
                self?.toggle(option)
            })
        }
        sheet.addAction(UIAlertAction(
            title: "common.cancel".localized,
            style: .cancel
        ))
        // iPad presents action sheets as popovers and crashes without an anchor.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = saveButton
            popover.sourceRect = saveButton.bounds
        }
        present(sheet, animated: true)
    }

    /// Tapping a ticked playlist removes the video, matching the web UI.
    private func toggle(_ option: PlaylistAddOption) {
        let removing = option.isAdded
        let actions = removing
            ? option.removeActions
            : option.addActions
        guard !actions.isEmpty else {
            showSaveError()
            return
        }
        saveButton.isEnabled = false
        engagementClient.editPlaylist(
            playlistId: option.id,
            actions: actions
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleEditResult(
                    result,
                    option: option,
                    removing: removing
                )
            }
        }
    }

    private func handleEditResult(
        _ result: Result<Void, Error>,
        option: PlaylistAddOption,
        removing: Bool
    ) {
        saveButton.isEnabled = true
        switch result {
        case .success:
            applyLocalToggle(option, removing: removing)
            if !removing {
                // The toast below carries the haptic half.
                Feedback.checkmark(on: saveButton)
            }
            let key = removing
                ? "player.action.removedFrom"
                : "player.action.savedTo"
            ToastView.show(
                key.localized(with: option.title),
                in: view
            )
        case .failure(let error):
            AppLog.player("playlist edit failed: \(error)")
            showSaveError()
        }
    }

    /// Keeps the sheet honest without refetching the whole option list.
    private func applyLocalToggle(
        _ option: PlaylistAddOption,
        removing: Bool
    ) {
        playlistOptions = playlistOptions?.map {
            guard $0.id == option.id else {
                return $0
            }
            return PlaylistAddOption(
                id: $0.id,
                title: $0.title,
                isAdded: !removing,
                addActions: $0.addActions,
                removeActions: $0.removeActions
            )
        }
        updateSaveButton()
    }

    private func showSaveError() {
        let alert = UIAlertController(
            title: "common.error".localized,
            message: "player.action.saveFailed".localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: "common.ok".localized,
            style: .default
        ))
        present(alert, animated: true)
    }
}
