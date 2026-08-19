import UIKit

// MARK: - Download settings pickers

extension SettingsViewController {
    func showDownloadQualityPicker() {
        let sheet = makeSheet("settings.row.downloadQuality")
        for option in DownloadPreferences.qualityOptions {
            let title = option == DownloadPreferences.askEveryTime
                ? "downloads.quality.ask".localized
                : option
            addChoice(
                title,
                to: sheet,
                isSelected: option == DownloadPreferences.quality
            ) {
                DownloadPreferences.quality = option
            }
        }
        present(sheet)
    }

    func showDownloadCommentsPicker() {
        let sheet = makeSheet("settings.row.downloadComments")
        for mode in DownloadPreferences.CommentsMode.allCases {
            addChoice(
                mode.displayName,
                to: sheet,
                isSelected: mode == DownloadPreferences.comments
            ) {
                DownloadPreferences.comments = mode
            }
        }
        present(sheet)
    }

    /// A pushed checklist, not a sheet: several languages can be on at once.
    func showDownloadCaptionsPicker() {
        navigationController?.pushViewController(
            CaptionLanguagesViewController(style: .grouped),
            animated: true
        )
    }

    private func makeSheet(_ titleKey: String) -> UIAlertController {
        UIAlertController(
            title: titleKey.localized,
            message: nil,
            preferredStyle: .actionSheet
        )
    }

    private func addChoice(
        _ title: String,
        to sheet: UIAlertController,
        isSelected: Bool,
        apply: @escaping () -> Void
    ) {
        let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
            apply()
            self?.reloadTable()
        }
        if isSelected {
            action.setValue(true, forKey: "checked")
        }
        sheet.addAction(action)
    }

    private func present(_ sheet: UIAlertController) {
        sheet.addAction(
            UIAlertAction(title: "common.cancel".localized, style: .cancel)
        )
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }
}
