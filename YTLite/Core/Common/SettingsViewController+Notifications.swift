import UIKit

// MARK: - Notifications settings row

extension SettingsViewController {
    func handleNotificationsSelection(_ row: Row) -> Bool {
        guard row == .notificationSettings else {
            return false
        }
        navigationController?.pushViewController(
            NotificationSettingsViewController(),
            animated: true
        )
        return true
    }
}
