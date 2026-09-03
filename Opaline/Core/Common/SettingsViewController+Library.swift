import UIKit

// MARK: - Library page
//
// The local library's own page rather than rows bolted onto Cache: this is
// user data with no other copy, not something regenerated on demand, and
// "Clear cache" and "Clear subscriptions" should not sit one tap apart.
//
// It stays visible while signed in, showing live counts, so signing in never
// reads as "my local library was destroyed".

extension SettingsViewController {
    var librarySections: [Section] {
        var historyRows: [Row] = [.saveLocalHistory]
        if LocalLibraryPreferences.savesHistory {
            historyRows.append(.localHistoryLimit)
        }
        historyRows.append(.clearLocalHistory)
        return [
            Section(
                header: "settings.section.library.history".localized,
                footer: "settings.footer.library".localized,
                rows: historyRows
            ),
            Section(
                header: "settings.section.library.subscriptions".localized,
                footer: libraryCountsFooter,
                rows: [.exportSubscriptions, .clearLocalSubscriptions]
            )
        ]
    }

    /// Live counts, and — while signed in — a line saying when any of this
    /// is actually used.
    private var libraryCountsFooter: String {
        let channels = LocalSubscriptionStore.shared.count
        let videos = LocalHistoryStore.shared.count
        let counts = "settings.library.counts".localized(
            with: channels, videos
        )
        guard OAuthClient.shared.isSignedIn else {
            return counts
        }
        return counts + " — "
            + "settings.library.usedWhenSignedOut".localized
    }

    func makeLibraryCell(_ row: Row) -> UITableViewCell? {
        switch row {
        case .saveLocalHistory:
            return makeToggleCell(
                "settings.row.saveLocalHistory".localized,
                isOn: LocalLibraryPreferences.savesHistory
            ) { [weak self] isOn in
                LocalLibraryPreferences.savesHistory = isOn
                self?.reloadAllSettings()
            }
        case .localHistoryLimit:
            return makeDisclosureCell(
                "settings.row.localHistoryLimit".localized,
                value: "\(LocalLibraryPreferences.historyLimit)"
            )
        case .clearLocalHistory:
            return makeLibraryDestructiveCell(
                "settings.row.clearLocalHistory".localized
            )
        case .clearLocalSubscriptions:
            return makeLibraryDestructiveCell(
                "settings.row.clearLocalSubscriptions".localized
            )
        case .exportSubscriptions:
            return makeDisclosureCell(
                "settings.row.exportSubscriptions".localized
            )
        default:
            return nil
        }
    }

    func handleLibrarySelection(_ row: Row) -> Bool {
        switch row {
        case .localHistoryLimit:
            showHistoryLimitPicker()
        case .clearLocalHistory:
            confirmClearLocalHistory()
        case .clearLocalSubscriptions:
            confirmClearLocalSubscriptions()
        case .exportSubscriptions:
            exportSubscriptions()
        default:
            return false
        }
        return true
    }

    private func makeLibraryDestructiveCell(
        _ title: String
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        cell.backgroundColor = ThemeManager.shared.surface
        return cell
    }
}

// MARK: - Actions

private extension SettingsViewController {
    func showHistoryLimitPicker() {
        let sheet = UIAlertController(
            title: "settings.row.localHistoryLimit".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        for limit in LocalLibraryPreferences.historyLimitOptions {
            let action = UIAlertAction(
                title: "\(limit)",
                style: .default
            ) { [weak self] _ in
                LocalLibraryPreferences.historyLimit = limit
                self?.reloadTable()
            }
            if limit == LocalLibraryPreferences.historyLimit {
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

    /// Confirmation is mandatory in a way it is not for Clear Cache: a cache
    /// comes back on its own, and this does not.
    func confirmClearLocalHistory() {
        confirmDestructive(
            title: "settings.row.clearLocalHistory".localized,
            message: "settings.library.clearHistory.confirm".localized
        ) { [weak self] in
            LocalHistoryStore.shared.clear()
            WatchProgressStore.shared.clearAll()
            self?.reloadAllSettings()
        }
    }

    func confirmClearLocalSubscriptions() {
        confirmDestructive(
            title: "settings.row.clearLocalSubscriptions".localized,
            message: "settings.library.clearSubscriptions.confirm".localized
        ) { [weak self] in
            LocalSubscriptionStore.shared.clear()
            AppCache.shared.clearLocalSubscriptionsFeed()
            self?.reloadAllSettings()
        }
    }

    func confirmDestructive(
        title: String,
        message: String,
        confirmed: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "common.cancel".localized, style: .cancel)
        )
        alert.addAction(
            UIAlertAction(title: title, style: .destructive) { _ in
                confirmed()
            }
        )
        present(alert, animated: true)
    }

    /// Same shape as `shareDebugLog()`: a temp file plus the system share
    /// sheet, which is all an export needs and costs no new UI. There is no
    /// import — no document-picker plumbing exists, and an import would tie
    /// this to an exported schema for good.
    func exportSubscriptions() {
        guard let data = LocalSubscriptionStore.shared.exportData(),
              LocalSubscriptionStore.shared.count > 0
        else {
            presentSimpleAlert(
                title: "settings.library.exportEmptyTitle".localized,
                message: "settings.library.exportEmptyMessage".localized
            )
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opaline_subscriptions.json")
        try? data.write(to: tempURL)
        AppLog.library(
            "exported \(LocalSubscriptionStore.shared.count) subscriptions"
        )
        let activity = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        configureCenteredPopover(activity)
        present(activity, animated: true)
    }
}
