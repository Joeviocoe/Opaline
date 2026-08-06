import UIKit

/// Messages.app-style multi-select editing: a bottom toolbar with
/// "Mark All Read" / "Delete", toggled by the left nav bar "Edit" item.
extension NotificationsViewController {
    func setupEditToolbar() {
        editToolbar.items = [
            markAllReadToolbarItem,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            deleteToolbarItem
        ]
        editToolbar.isHidden = true
        editToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editToolbar)
        NSLayoutConstraint.activate([
            editToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            editToolbar.heightAnchor.constraint(
                equalToConstant: NotificationsViewController.editToolbarHeight
            )
        ])
    }

    func applyEditToolbarTheme() {
        let theme = ThemeManager.shared
        editToolbar.barTintColor = theme.surface
        editToolbar.tintColor = theme.primaryText
        deleteToolbarItem.tintColor = .systemRed
    }

    @objc
    func editTapped() {
        setEditingMode(!tableView.isEditing)
    }

    func setEditingMode(_ editing: Bool) {
        // Order matters: cells already on screen pick their editing control
        // when `setEditing` runs, so multi-select has to be on first —
        // otherwise they get delete badges and only recycled cells get
        // checkmarks.
        tableView.allowsMultipleSelectionDuringEditing = editing
        tableView.setEditing(editing, animated: true)
        editButton.title = (editing ? "common.cancel" : "common.edit").localized
        editToolbar.isHidden = !editing
        let inset: CGFloat = editing ? NotificationsViewController.editToolbarHeight : 0
        tableView.contentInset.bottom = inset
        tableView.scrollIndicatorInsets.bottom = inset
        updateToolbarButtonsState()
    }

    /// "Mark all read" is only offered with nothing selected; "Delete"
    /// only once at least one row is selected.
    func updateToolbarButtonsState() {
        let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0
        markAllReadToolbarItem.isEnabled = selectedCount == 0
            && AppNotificationStore.shared.unreadCount > 0
        deleteToolbarItem.isEnabled = selectedCount > 0
    }

    @objc
    func markAllReadTapped() {
        AppNotificationStore.shared.markAllRead()
    }

    @objc
    func deleteSelectedTapped() {
        guard let indexPaths = tableView.indexPathsForSelectedRows, !indexPaths.isEmpty else {
            return
        }
        // Snapshot ids before removing — indexes shift after each removal,
        // but `remove(id:)` looks items up by id so order doesn't matter.
        let ids = indexPaths.map { items[$0.row].id }
        ids.forEach { AppNotificationStore.shared.remove(id: $0) }
    }
}
