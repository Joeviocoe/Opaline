import Foundation

/// Which player a short opens in when tapped from a feed.
///
/// Temporary (issue #34): the vertical viewer still lacks a seek bar,
/// captions and the overflow menu, so the regular player stays available
/// as an escape hatch until it catches up.
enum ShortsPlayerMode: String, CaseIterable {
    case vertical = "vertical_viewer"
    case regular = "watch_player"

    static var selected: ShortsPlayerMode {
        get {
            let raw = UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Feed.shortsPlayer
            )
            return raw.flatMap(ShortsPlayerMode.init) ?? .vertical
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: UserDefaultsKeys.Feed.shortsPlayer
            )
        }
    }

    var displayName: String {
        switch self {
        case .vertical:
            return "settings.shortsPlayer.vertical".localized
        case .regular:
            return "settings.shortsPlayer.regular".localized
        }
    }
}

/// On: each fetched page's shorts collapse into their own shelf in the
/// subscriptions feed. Off: they stay inline as ordinary videos.
enum ShortsGrouping {
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Feed.groupShorts
            ) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Feed.groupShorts
            )
            NotificationCenter.default.post(
                name: .shortsGroupingSettingDidChange, object: nil
            )
        }
    }
}

/// Whether the Subscriptions screen carries Shorts at all — the whole list
/// and a single filtered channel alike.
///
/// Off by default, unlike the global Shorts setting. Subscriptions is the
/// screen people go to for the videos of channels they chose, and a shelf of
/// short-form in the middle of it is not what most of them are looking for.
/// On this hardware it also costs the most: each short resolved for the
/// vertical viewer builds a synthesized progressive MP4.
enum SubscriptionsShorts {
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Feed.subscriptionsShowShorts
            ) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: UserDefaultsKeys.Feed.subscriptionsShowShorts
            )
            NotificationCenter.default.post(
                name: .subscriptionsShortsSettingDidChange, object: nil
            )
        }
    }
}

extension Notification.Name {
    static let shortsGroupingSettingDidChange = Notification.Name(
        "shortsGroupingSettingDidChange"
    )
    static let subscriptionsShortsSettingDidChange = Notification.Name(
        "subscriptionsShortsSettingDidChange"
    )
}
