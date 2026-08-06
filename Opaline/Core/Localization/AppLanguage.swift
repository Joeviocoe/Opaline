import Foundation

/// UI languages the app ships `.lproj` bundles for. Adding a language =
/// adding its case + a translated `Localizable.strings`
/// (see docs/plans/localization.md, Phase 4). The full 67-language set lives
/// on the `archive/all-languages` branch — this list is the curated set
/// (en/ru/uk + Steam/W3Techs web-population leaders); restore a language by
/// cherry-picking its `.lproj` and re-adding the case. RTL languages are
/// deferred until a leading/trailing constraint audit.
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
        if let override {
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
            "English"
        case .russian:
            "Русский"
        case .ukrainian:
            "Українська"
        case .german:
            "Deutsch"
        case .spanish:
            "Español"
        case .french:
            "Français"
        case .italian:
            "Italiano"
        case .japanese:
            "日本語"
        case .portuguese:
            "Português"
        case .turkish:
            "Türkçe"
        case .chineseSimplified:
            "简体中文"
        case .chineseTraditional:
            "繁體中文"
        }
    }
}
