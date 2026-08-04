import Foundation

/// Resolves the active strings bundle. Following the system uses the main
/// bundle (iOS picks the `.lproj` itself); an in-app override resolves that
/// language's bundle directly — required on iOS 12, where per-app language
/// in the Settings app does not exist (it arrived in iOS 13).
final class LocalizationManager {
    static let shared = LocalizationManager()

    private(set) var bundle: Bundle = .main
    /// Every `.lproj` is a separate table: a key missing from the active
    /// language is NOT looked up in the development language, the lookup
    /// just hands back the key. This is the fallback that does that.
    private lazy var englishBundle: Bundle? = Bundle.main
        .path(forResource: "en", ofType: "lproj")
        .flatMap(Bundle.init(path:))
    /// Sentinel rather than comparing against the key, so a translation that
    /// legitimately equals its key isn't mistaken for a miss.
    private let missing = "\u{0}missing"

    private init() {
        reload()
    }

    /// Re-resolves the bundle after a language change. UI built before the
    /// change keeps its strings — the caller decides between rebuilding the
    /// root controller and a restart prompt (see the localization plan).
    func reload() {
        guard let code = AppLanguage.override?.rawValue,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path) else {
            bundle = .main
            return
        }
        bundle = localized
    }

    func localized(_ key: String) -> String {
        let value = bundle.localizedString(
            forKey: key, value: missing, table: nil
        )
        guard value == missing else {
            return value
        }
        return englishBundle?.localizedString(
            forKey: key, value: key, table: nil
        ) ?? key
    }
}

extension String {
    /// Localized UI string — ALL user-facing text goes through this, never
    /// `NSLocalizedString` directly: the in-app language override needs
    /// [[LocalizationManager]]'s bundle resolution. A key missing from the
    /// active language falls back to English, then to the key itself — see
    /// `LocalizationManager.localized(_:)`, the runtime does not do this.
    var localized: String {
        LocalizationManager.shared.localized(self)
    }

    /// Localized format string applied to `args`. Use positional
    /// placeholders (`%1$@`) whenever a translation could reorder them.
    func localized(with args: CVarArg...) -> String {
        String(format: localized, arguments: args)
    }
}
