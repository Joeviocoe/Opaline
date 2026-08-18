import UIKit

/// Builds the playback chain: which ways of playing a video are on, and the
/// order they are tried in.
///
/// Replaces the old single-source picker. Which client and delivery works is
/// YouTube's decision to change, not ours to hardcode — this puts the order in
/// the user's hands so a break can be worked around without a release.
final class PlaybackChainViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let registry: PlaybackStepRegistry
    private var order: [String]
    private var enabled: Set<String>

    init(registry: PlaybackStepRegistry = .default) {
        self.registry = registry
        order = PlaybackChainSettings.order
        enabled = PlaybackChainSettings.enabled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "settings.row.playbackChain".localized
        view.backgroundColor = ThemeManager.shared.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = ThemeManager.shared.background
        // Editing mode is what gives iOS 12 its reorder grips; there is no
        // drag-and-drop API on this OS worth the trouble.
        tableView.setEditing(true, animated: false)
        tableView.allowsSelectionDuringEditing = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func steps() -> [PlaybackStep] {
        order.compactMap { registry.step(id: $0) }
    }

    private func persist() {
        PlaybackChainSettings.order = order
        PlaybackChainSettings.enabled = enabled
    }

    @objc
    private func toggleStep(_ toggle: UISwitch) {
        let steps = steps()
        guard toggle.tag < steps.count else {
            return
        }
        let id = steps[toggle.tag].id
        guard toggle.isOn || enabled.count > 1 else {
            // Switching off the last one leaves nothing to play with, and the
            // app would only find out at the next video.
            toggle.setOn(true, animated: true)
            return
        }
        if toggle.isOn {
            enabled.insert(id)
        } else {
            enabled.remove(id)
        }
        persist()
        tableView.reloadData()
    }
}

// MARK: - Table

extension PlaybackChainViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        steps().count
    }

    func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let step = steps()[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = step.title
        cell.textLabel?.textColor = ThemeManager.shared.primaryText
        cell.backgroundColor = ThemeManager.shared.surface
        cell.selectionStyle = .none
        cell.showsReorderControl = true
        let signInNeeded = step.requiresSignIn && !OAuthClient.shared.isSignedIn
        if signInNeeded {
            cell.detailTextLabel?.text = "settings.playbackChain.signInNeeded".localized
            cell.detailTextLabel?.textColor = ThemeManager.shared.secondaryText
        }
        let toggle = UISwitch()
        toggle.isOn = enabled.contains(step.id)
        toggle.isEnabled = !signInNeeded
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleStep(_:)), for: .valueChanged)
        cell.editingAccessoryView = toggle
        return cell
    }

    func tableView(
        _ tableView: UITableView, titleForFooterInSection section: Int
    ) -> String? {
        "settings.playbackChain.footer".localized
    }

    func tableView(
        _ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(
        _ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath
    ) -> Bool {
        false
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        let moved = order.remove(at: sourceIndexPath.row)
        order.insert(moved, at: destinationIndexPath.row)
        persist()
        tableView.reloadData()
    }
}
