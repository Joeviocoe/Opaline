import UIKit

/// Which subtitle languages downloads bring with them. A checklist rather
/// than a picker: several answers are the point, and an action sheet closes
/// on the first tap.
///
/// The list is the app's own languages. A video's tracks are not known until
/// one is chosen, and a catalogue of every language on earth would be a large
/// screen for a setting opened once.
final class CaptionLanguagesViewController: UITableViewController {
    private let languages = AppLanguage.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "settings.row.downloadCaptions".localized
        tableView.tableFooterView = UIView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        languages.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        "settings.footer.downloadCaptions".localized
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let language = languages[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let theme = ThemeManager.shared
        cell.textLabel?.text = language.displayName
        cell.textLabel?.textColor = theme.primaryText
        cell.backgroundColor = theme.surface
        cell.tintColor = theme.accent
        cell.accessoryType = DownloadPreferences.captionLanguages
            .contains(language.rawValue) ? .checkmark : .none
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        let code = languages[indexPath.row].rawValue
        var picked = DownloadPreferences.captionLanguages
        if picked.contains(code) {
            picked.remove(code)
        } else {
            picked.insert(code)
        }
        DownloadPreferences.captionLanguages = picked
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        tableView.reloadData()
    }
}
