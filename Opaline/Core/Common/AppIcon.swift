import UIKit

/// The app icon the user forced, if any.
///
/// `auto` sets no alternate icon at all — from iOS 18 the system picks the
/// light or dark artwork from the asset catalog itself, so there is nothing
/// to do. Older systems have no such thing, which is why `auto` is only
/// offered where it means something.
enum AppIcon: String, CaseIterable {
    case auto = "auto"
    case light = "AppIconLight"
    case dark = "AppIconDark"
    case clearLight = "AppIconClearLight"
    case clearDark = "AppIconClearDark"

    static var available: [AppIcon] {
        if #available(iOS 18.0, *) {
            return allCases
        }
        return [.light, .dark, .clearLight, .clearDark]
    }

    /// What the system currently shows, mapped back onto our options.
    static var selected: AppIcon {
        let name = UIApplication.shared.alternateIconName
        return name.flatMap(AppIcon.init(rawValue:)) ?? available[0]
    }

    var alternateIconName: String? {
        self == .auto ? nil : rawValue
    }

    /// The artwork, for the picker rows. Auto has none of its own — it
    /// shows whichever variant the current theme is wearing.
    var previewImage: UIImage? {
        let name = self == .auto
            ? (ThemeManager.shared.isDark ? AppIcon.dark : AppIcon.light).rawValue
            : rawValue
        return UIImage(named: name)
    }

    var displayName: String {
        switch self {
        case .auto:
            return "settings.theme.auto".localized
        case .light:
            return "settings.theme.light".localized
        case .dark:
            return "settings.theme.dark".localized
        // Proper nouns, like the Composer variants they came from — the
        // same in every language, so no keys for them.
        case .clearLight:
            return "Clear Light"
        case .clearDark:
            return "Clear Dark"
        }
    }

    /// iOS shows its own confirmation alert on every change — unavoidable
    /// through the public API, so the completion only logs failures.
    func apply() {
        guard UIApplication.shared.supportsAlternateIcons else {
            AppLog.log("Icon", "alternate icons unsupported")
            return
        }
        UIApplication.shared.setAlternateIconName(alternateIconName) { error in
            if let error {
                AppLog.log("Icon", "app icon \(self.rawValue) failed: \(error)")
            }
        }
    }
}
