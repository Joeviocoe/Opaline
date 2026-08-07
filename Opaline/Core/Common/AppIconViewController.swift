import UIKit

/// Icon picker: one row per option, artwork on the left, checkmark on the
/// current one. The pick applies immediately — iOS puts up its own
/// confirmation alert, so there is nothing to confirm here.
final class AppIconViewController: UIViewController {
    private lazy var tableView: UITableView = {
        if #available(iOS 13, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()

    private let options = AppIcon.available
    private var selected = AppIcon.selected

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "settings.row.appIcon".localized
        tableView.register(
            AppIconCell.self,
            forCellReuseIdentifier: AppIconCell.reuseID
        )
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 76
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
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

// MARK: - Data source / delegate

extension AppIconViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AppIconCell.reuseID,
            for: indexPath
        )
        let icon = options[indexPath.row]
        (cell as? AppIconCell)?.configure(
            icon: icon,
            isSelected: icon == selected
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let icon = options[indexPath.row]
        guard icon != selected else {
            return
        }
        selected = icon
        icon.apply()
        tableView.reloadData()
    }
}

// MARK: - Cell

private final class AppIconCell: UITableViewCell {
    static let reuseID = "AppIconCell"

    private let artwork = UIImageView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        artwork.contentMode = .scaleAspectFit
        // Home-screen squircle is not reproducible with a corner radius, but
        // at 60pt the difference is invisible; iOS uses ~13.5 there.
        artwork.layer.cornerRadius = 13.5
        artwork.clipsToBounds = true
        artwork.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 16
            ),
            artwork.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 60),
            artwork.heightAnchor.constraint(equalToConstant: 60),
            label.leadingAnchor.constraint(
                equalTo: artwork.trailingAnchor, constant: 16
            ),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor, constant: -16
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(icon: AppIcon, isSelected: Bool) {
        let theme = ThemeManager.shared
        artwork.image = icon.previewImage
        label.text = icon.displayName
        label.textColor = theme.primaryText
        backgroundColor = theme.surface
        accessoryType = isSelected ? .checkmark : .none
        tintColor = theme.accent
    }
}
