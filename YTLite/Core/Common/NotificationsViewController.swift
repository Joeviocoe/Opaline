import UIKit

/// Notification inbox — presented as a sheet, like Settings.
final class NotificationsViewController: UIViewController {
    static let editToolbarHeight: CGFloat = 44

    lazy var tableView = UITableView(frame: .zero, style: .plain)
    private let bannerView = NotificationPermissionBannerView()
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "notifications.empty".localized
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 15)
        return label
    }()

    var items: [AppNotification] { AppNotificationStore.shared.notifications }
    lazy var editButton = UIBarButtonItem(
        title: "common.edit".localized,
        style: .plain,
        target: self,
        action: #selector(editTapped)
    )
    /// Bottom toolbar shown only while editing, mirroring Messages.app.
    lazy var editToolbar = UIToolbar()
    lazy var markAllReadToolbarItem = UIBarButtonItem(
        title: "notifications.markAllRead".localized,
        style: .plain,
        target: self,
        action: #selector(markAllReadTapped)
    )
    lazy var deleteToolbarItem = UIBarButtonItem(
        title: "common.delete".localized,
        style: .plain,
        target: self,
        action: #selector(deleteSelectedTapped)
    )
    /// Set right before a local `deleteRows` animation so the async
    /// `didChangeNotification` it triggers doesn't also fire a full
    /// `reloadData`, which would crash fighting the in-flight row animation.
    var suppressNextReload = false

    /// Wraps the inbox in the shared sheet presentation, so other call
    /// sites (bell button, notification taps) can reuse the same chrome.
    static func present(from vc: UIViewController) {
        let nav = RotatingNavigationController(rootViewController: NotificationsViewController())
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        vc.present(nav, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "notifications.title".localized
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "common.done".localized,
            style: .done,
            target: self,
            action: #selector(dismissTapped)
        )
        navigationItem.leftBarButtonItem = editButton
        bannerView.onEnable = { [weak self] in self?.handleEnableTapped() }
        setupTableView()
        setupEditToolbar()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: AppNotificationStore.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshBanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !bannerView.isHidden,
              tableView.tableHeaderView?.frame.width != tableView.bounds.width
        else {
            return
        }
        updateBannerHeader()
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        // Background checks are throttled to 12h; pull-to-refresh is the
        // manual way to ask right now.
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        tableView.refreshControl = refresh
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
        emptyLabel.textColor = theme.secondaryText
        bannerView.applyTheme()
        applyEditToolbarTheme()
        reload()
    }

    @objc
    private func reload() {
        guard !suppressNextReload else {
            suppressNextReload = false
            return
        }
        tableView.reloadData()
        updateEmptyState()
        updateToolbarButtonsState()
    }

    @objc
    private func refreshPulled() {
        UpdateNotificationService.shared.checkIfNeeded(force: true) { [weak self] _ in
            self?.tableView.refreshControl?.endRefreshing()
        }
    }

    @objc
    private func dismissTapped() {
        dismiss(animated: true)
    }

    private func refreshBanner() {
        SystemNotificationAuthorization.status { [weak self] status in
            guard let self else {
                return
            }
            // Opening the inbox is the first moment the user has shown
            // interest, so ask here; iOS only ever shows the prompt once,
            // and the banner covers the "user said no" case afterwards.
            if status == .notDetermined {
                SystemNotificationAuthorization.request { _ in self.refreshBanner() }
                return
            }
            self.bannerView.isHidden = status == .authorized
            self.updateBannerHeader()
        }
    }

    /// Table header views need an explicit frame, so the banner can only be
    /// sized once the table has a width — hence the retry from layout.
    private func updateBannerHeader() {
        guard !bannerView.isHidden else {
            tableView.tableHeaderView = nil
            return
        }
        guard tableView.bounds.width > 0 else {
            return
        }
        tableView.tableHeaderView = bannerView.sized(for: tableView.bounds.width)
    }

    private func handleEnableTapped() {
        SystemNotificationAuthorization.status { [weak self] status in
            guard let self else {
                return
            }
            if status == .notDetermined {
                SystemNotificationAuthorization.request { _ in self.refreshBanner() }
            } else {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func updateEmptyState() {
        // The table sizes its background view for us; the label centers
        // its text vertically inside those bounds.
        tableView.backgroundView = items.isEmpty ? emptyLabel : nil
    }
}

// MARK: - Data source / delegate

extension NotificationsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let theme = ThemeManager.shared
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.textLabel?.text = item.title
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = item.isRead
            ? UIFont.systemFont(ofSize: 15)
            : UIFont.boldSystemFont(ofSize: 15)
        cell.textLabel?.textColor = theme.primaryText
        cell.detailTextLabel?.text = DateFormatter.notificationsDisplay.string(from: item.date)
        cell.detailTextLabel?.textColor = theme.secondaryText
        cell.backgroundColor = theme.surface
        // The default selection grey is near-white and blows out the text on
        // the dark theme; a tint of the text colour works in both.
        let selected = UIView()
        selected.backgroundColor = theme.primaryText.withAlphaComponent(0.1)
        cell.selectedBackgroundView = selected
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else {
            return
        }
        suppressNextReload = true
        AppNotificationStore.shared.remove(id: items[indexPath.row].id)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        updateEmptyState()
        updateToolbarButtonsState()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !tableView.isEditing else {
            updateToolbarButtonsState()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        AppNotificationStore.shared.markRead(id: item.id)
        navigationController?.pushViewController(
            NotificationDetailViewController(item: item),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard tableView.isEditing else {
            return
        }
        updateToolbarButtonsState()
    }
}

private extension DateFormatter {
    static let notificationsDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
