import UIKit

// MARK: - About rows
//
// Issue forms ask for the app version, the OS version and the device model.
// The system Settings app localizes the model name and omits the "iPadOS"
// prefix, so every value is shown — and copied — here in the exact form an
// issue needs: identifiers, not marketing names.

extension SettingsViewController {
    var appVersionValue: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// `UIDevice.systemName` only reports "iPadOS" on iOS 13+; the idiom is
    /// the same answer on every version.
    var systemVersionValue: String {
        let name = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        return "\(name) \(UIDevice.current.systemVersion)"
    }

    /// `iPad12,2` — the identifier is the same string in every language.
    var deviceModelValue: String {
        var info = utsname()
        uname(&info)
        var machine = info.machine
        let size = MemoryLayout.size(ofValue: machine)
        return withUnsafePointer(to: &machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: size) {
                String(cString: $0)
            }
        }
    }

    func aboutValue(for row: Row) -> String? {
        switch row {
        case .aboutVersion:
            return appVersionValue
        case .aboutSystem:
            return systemVersionValue
        case .aboutModel:
            return deviceModelValue
        default:
            return nil
        }
    }

    private func aboutTitle(for row: Row) -> String {
        switch row {
        case .aboutSystem:
            return "settings.about.system".localized
        case .aboutModel:
            return "settings.about.model".localized
        default:
            return "settings.about.version".localized
        }
    }

    func makeAboutCell(_ row: Row) -> UITableViewCell {
        let theme = ThemeManager.shared
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text            = aboutTitle(for: row)
        cell.textLabel?.textColor       = theme.primaryText
        cell.detailTextLabel?.text      = aboutValue(for: row)
        cell.detailTextLabel?.textColor = theme.secondaryText
        cell.backgroundColor            = theme.surface
        let icon = UIImageView(image: UIImage(named: "icon_copy"))
        icon.tintColor = theme.secondaryText
        icon.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        cell.accessoryView = icon
        return cell
    }

    func handleAboutSelection(_ row: Row) -> Bool {
        guard let value = aboutValue(for: row) else {
            return false
        }
        UIPasteboard.general.string = value
        ToastView.show("common.copied".localized, in: view)
        return true
    }
}
