import Foundation

/// UI languages the app ships `.lproj` bundles for. Adding a language =
/// adding its case + a translated `Localizable.strings`, worded from the
/// official YouTube app's own `.lproj` for that language (see the
/// Localization section in AGENTS.md). RTL languages are deferred until a
/// leading/trailing constraint audit.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"
    case ukrainian = "uk"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case japanese = "ja"
    case portuguese = "pt"
    case turkish = "tr"
    case vietnamese = "vi"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"

    /// The user's in-app override, nil = follow the system language.
    static var override: AppLanguage? {
        get {
            let stored = UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Localization.appLanguage
            )
            return stored.flatMap(AppLanguage.init(rawValue:))
        }
        set {
            UserDefaults.standard.set(
                newValue?.rawValue,
                forKey: UserDefaultsKeys.Localization.appLanguage
            )
            LocalizationManager.shared.reload()
        }
    }

    /// The effective UI language: the override, else the closest supported
    /// match to the system language, else English.
    static var effective: AppLanguage {
        if let override = override {
            return override
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if let lang = AppLanguage(rawValue: preferred) {
            return lang
        }
        let parts = preferred.split(separator: "-")
        if parts.count >= 2 {
            let withoutRegion = parts.prefix(2).joined(separator: "-")
            if let lang = AppLanguage(rawValue: withoutRegion) {
                return lang
            }
        }
        let langCode = String(preferred.prefix(2))
        return AppLanguage(rawValue: langCode) ?? .english
    }
}

// MARK: - Display names

extension AppLanguage {
    /// Native-script name for the settings picker.
    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .russian:
            return "Русский"
        case .ukrainian:
            return "Українська"
        case .german:
            return "Deutsch"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        case .italian:
            return "Italiano"
        case .japanese:
            return "日本語"
        case .portuguese:
            return "Português"
        case .turkish:
            return "Türkçe"
        case .vietnamese:
            return "Tiếng Việt"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        }
    }
}
