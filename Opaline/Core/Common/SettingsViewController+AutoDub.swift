import UIKit

// MARK: - Auto-dub settings (start videos dubbed)
//
// Applies from the next opened video — no restart needed, so unlike the
// language rows these pickers show no restart alert.

extension SettingsViewController {
    // MARK: Cells

    func makeAutoDubToggleCell() -> UITableViewCell {
        makeToggleCell(
            "settings.row.autoDub".localized,
            isOn: AutoDubPreference.isEnabled
        ) { [weak self] isOn in
            AutoDubPreference.isEnabled = isOn
            self?.reloadAutoDubSection()
        }
    }

    func makeAutoDubLanguageCell() -> UITableViewCell {
        let value: String
        if let code = AutoDubPreference.languageOverride {
            value = dubLanguageName(code)
        } else {
            value = "settings.language.system".localized
                + " (\(AutoDubPreference.effectiveLanguageCode))"
        }
        return makeDisclosureCell(
            "settings.row.autoDubLanguage".localized, value: value
        )
    }

    func makeAutoDubIgnoreAICell() -> UITableViewCell {
        makeToggleCell(
            "settings.row.autoDubIgnoreAI".localized,
            isOn: AutoDubPreference.ignoreAIDubs
        ) {
            AutoDubPreference.ignoreAIDubs = $0
        }
    }

    // MARK: Selection

    func handleAutoDubSelection(_ row: Row) -> Bool {
        guard row == .autoDubLanguage else {
            return false
        }
        showAutoDubLanguagePicker()
        return true
    }

    // MARK: - Private

    /// CLDR name in the app's UI language, like the other language rows.
    private func dubLanguageName(_ code: String) -> String {
        Locale(identifier: AppLanguage.effective.rawValue)
            .localizedString(forLanguageCode: code)?
            .capitalized ?? code
    }

    private func showAutoDubLanguagePicker() {
        let sheet = UIAlertController(
            title: "settings.row.autoDubLanguage".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        let options: [(String?, String)] =
            [(nil, "settings.language.system".localized)]
            + AppLanguage.allCases.map { ($0.rawValue, $0.displayName) }
        let selected = AutoDubPreference.languageOverride
        for (code, name) in options {
            let action = UIAlertAction(
                title: name, style: .default
            ) { [weak self] _ in
                AutoDubPreference.languageOverride = code
                self?.reloadAllSettings()
            }
            if code == selected {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(
            UIAlertAction(title: "common.cancel".localized, style: .cancel)
        )
        configureCenteredPopover(sheet)
        present(sheet, animated: true)
    }

    private func reloadAutoDubSection() {
        reloadSection(containing: .autoDubEnabled)
    }
}
