import Foundation

/// Whether the local library is the active source right now.
///
/// Keyed on `isSignedIn`, not `isAnonymous`: there are three auth states,
/// and only "has a live account" should route to the server. Auth
/// transitions rebuild the whole view-controller tree (`showAuth`/`showMain`
/// replace the window's root), so a screen deciding this once at
/// construction never has to watch for it changing underneath.
enum LocalLibrary {
    static var isActive: Bool {
        !OAuthClient.shared.isSignedIn
    }
}

/// User-facing settings for the local library. Preferences, not data —
/// the data lives in `Application Support/LocalLibrary/`.
enum LocalLibraryPreferences {
    static let historyLimitOptions = [100, 500, 1_000]
    static let defaultHistoryLimit = 500

    /// Some people choose signed-out *precisely* to avoid a watch history,
    /// so this has to be switchable — and defaults on, because a history
    /// that silently records nothing is the worse surprise of the two.
    static var savesHistory: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.LocalLibrary.savesHistory
            ) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.LocalLibrary.savesHistory
            )
            AppLog.library("prefs: savesHistory=\(newValue)")
        }
    }

    static var historyLimit: Int {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.LocalLibrary.historyLimit
            ) as? Int ?? defaultHistoryLimit
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.LocalLibrary.historyLimit
            )
            AppLog.library("prefs: historyLimit=\(newValue)")
        }
    }
}
