import UIKit

// "Notifications" settings screen — single toggle for app-update checks.
// swiftlint:disable:next type_name
final class NotificationSettingsViewController: UIViewController {
    private lazy var tableView: UITableView = {
        if #available(iOS 13, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "settings.row.notifications".localized
        // Titled, not `barButtonSystemItem: .done` — system items follow the
        // device language, ignoring the in-app override.
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "common.done".localized,
            style: .done,
            target: self,
            action: #selector(dismissTapped)
        )
        setupTableView()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    private func setupTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.allowsSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        tableView.separatorColor = theme.separator
        tableView.reloadData()
    }

    @objc
    private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc
    private func updatesToggled(_ sender: UISwitch) {
        UpdateNotificationService.updatesEnabled = sender.isOn
        guard sender.isOn else {
            return
        }
        SystemNotificationAuthorization.status { status in
            guard status == .notDetermined else {
                return
            }
            SystemNotificationAuthorization.request { _ in }
        }
    }
}

// MARK: - Data source / delegate

extension NotificationSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "settings.footer.notifications".localized
    }

    func tableView(
        _ tableView: UITableView,
        willDisplayFooterView view: UIView,
        forSection section: Int
    ) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.textColor =
            ThemeManager.shared.secondaryText
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let theme = ThemeManager.shared
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = "settings.row.appUpdates".localized
        cell.textLabel?.textColor = theme.primaryText
        cell.backgroundColor = theme.surface
        let toggle = UISwitch()
        toggle.isOn = UpdateNotificationService.updatesEnabled
        toggle.addTarget(self, action: #selector(updatesToggled), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }
}
