import Foundation

/// Autoplay-next policy, independently toggleable per queue kind:
/// suggestion ("Up Next") videos show a 5s countdown overlay before
/// advancing, mix/playlist queues advance instantly since waiting makes no
/// sense for short music clips. Consulted in
/// `WatchViewController+PlayerObserving.playerItemDidPlayToEnd`.
enum AutoplayPreference {
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Autoplay.enabled
            ) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Autoplay.enabled
            )
        }
    }

    static var isMixEnabled: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Autoplay.mixEnabled
            ) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Autoplay.mixEnabled
            )
        }
    }
}
