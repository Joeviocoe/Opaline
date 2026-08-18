import Foundation

/// Centralised UserDefaults key namespace.
/// All keys used in the app must be declared here to prevent typos and collisions.
enum UserDefaultsKeys {
    enum Theme {
        static let mode = "themeMode"
        static let autoDarkStartHour = "theme_autoDarkStartHour"
        static let autoDarkEndHour = "theme_autoDarkEndHour"
    }

    enum VideoQuality {
        static let selected = "defaultVideoQuality"
    }

    enum Cache {
        static let feedPersistenceEnabled = "feedCachePersistenceEnabled"
        static let feedCacheDays = "feedCacheDays"
        static let imageCacheEnabled = "imageCacheEnabled"
        static let imageCacheDays = "imageCacheDays"
        static let thumbnailQuality = "thumbnailQuality"

        /// When a feed was last written — read on launch to decide whether
        /// the screen may skip its network revalidation. Cheaper than
        /// reading the cache file just for its timestamp.
        static func feedUpdatedAt(_ feedKey: String) -> String {
            "cache_feedUpdatedAt_\(feedKey)"
        }
    }

    enum Auth {
        static let isAnonymous = "isAnonymous"
    }

    enum RYD {
        static let enabled    = "ryd_enabled"
        static let userId     = "ryd_userId_v2"
        static let registered = "ryd_registered_v2"
    }

    enum SponsorBlock {
        static let enabled = "sponsorblock_enabled"
        /// Returns the key for the skip-behavior setting of a given category raw value.
        static func segmentBehavior(for categoryRawValue: String) -> String {
            "sb_behavior_\(categoryRawValue)"
        }
    }

    enum Feed {
        static let showShorts = "feed_showShorts"
        /// `ShortsPlayerMode` raw value; absent = vertical viewer.
        static let shortsPlayer = "feed_shortsPlayer"
        /// Shorts shelf in the subscriptions feed; absent = grouped.
        static let groupShorts = "feed_groupShorts"
        static let homeLayout = "feed_homeLayout"
        /// `DefaultTab` raw value (= tab tag); absent = Home.
        static let defaultTab = "feed_defaultTab"
    }

    enum Search {
        static let history = "search_history"
    }

    enum Localization {
        /// In-app UI language override; absent = follow the system.
        static let appLanguage = "localization_appLanguage"
        /// Innertube `gl`; absent = device region.
        static let region = "localization_region"
    }

    enum Account {
        /// The signed-in user's own channel id, derived from the accounts
        /// list (`UC` + `offlineCacheKeyToken.clientCacheKey`).
        static let ownChannelId = "account_ownChannelId"
    }

    enum Playlists {
        /// Legacy "Favorites" playlist id (`FL` + channelId). The TV library
        /// browse omits it, so it is remembered the first time the
        /// add-to-playlist options mention it.
        static let legacyFavoritesId = "playlists_legacyFavoritesId"
    }

    enum Player {
        static let backgroundPlayback = "player_backgroundPlayback"
        static let pipEnabled = "player_pipEnabled"
        static let hideStatusBarInFullscreen = "player_hideStatusBarFullscreen"
        static let autoZoomToFill = "player_autoZoomToFill"
    }

    enum Playback {
        /// The made-up television id the TV client presents once and keeps;
        /// its proof-of-origin token is bound to this exact string.
        static let livingRoomPoTokenId = "playback_livingRoomPoTokenId"
    }

    enum AutoDub {
        static let enabled = "autoDub_enabled"
        static let ignoreAIDubs = "autoDub_ignoreAIDubs"
        /// Preferred dub language code; absent = follow the app language.
        static let language = "autoDub_language"
    }

    enum Autoplay {
        /// Suggestion ("Up Next") autoplay: 5s countdown overlay.
        static let enabled = "autoplay_enabled"
        /// Mix/playlist queue autoplay: instant, no overlay.
        static let mixEnabled = "autoplay_mixEnabled"
    }

    enum Innertube {
        static let visitorData = "innertube_visitorData"
        static let visitorDataDate = "innertube_visitorDataDate"
    }

    enum Debug {
        static let playbackSource = "debug_playbackSource"
        static let streamDelivery = "debug_streamDelivery"
        static let serverBaseURL = "debug_serverBaseURL"
        static let mainThreadWatchdog = "debug_mainThreadWatchdog"
    }

    enum Migration {
        static let playbackSourceAuto = "migration_playbackSourceAuto"
        /// Tokens stored before the keychain item became readable while the
        /// device is locked.
        static let keychainAfterFirstUnlock = "migration_keychainAfterFirstUnlock"
    }

    enum Notifications {
        static let appUpdatesEnabled = "notifications_appUpdates"
        static let lastUpdateCheck = "notifications_lastUpdateCheck"
        /// First launch of a build that has the inbox — nothing published
        /// before it is worth showing.
        static let featureInstallDate = "notifications_featureInstallDate"
    }
}

// MARK: - PlaybackSource

/// Case order is the order of the picker: the working sources first, the
/// broken one last.
enum PlaybackSource: String, CaseIterable {
    case auto = "auto"
    case visionOS = "visionos"
    case androidVR = "android_vr"
    case tv = "tv"
    case progressive = "progressive"
    case mwebPot = "mweb_pot"

    static var selected: PlaybackSource {
        let raw = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.Debug.playbackSource
        )
        return raw.flatMap(PlaybackSource.init)
            ?? .auto
    }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto (visionOS, TV fallback)"
        case .visionOS:
            return "visionOS (anonymous, SABR)"
        case .androidVR:
            return "Android VR (capped at 1 min)"
        case .progressive:
            return "Progressive (360p)"
        case .mwebPot:
            return "Mobile Web + pot (broken)"
        case .tv:
            return "TV (signed in, SABR)"
        }
    }

    /// Whether this source has a choice of delivery at all.
    ///
    /// The anonymous clients hand out formats that carry a `url`, so their
    /// bytes can arrive either way. Progressive plays a single muxed URL, and
    /// mweb is built around its own pot-bound URLs — neither has anything to
    /// switch between.
    var supportsDeliveryChoice: Bool {
        switch self {
        case .auto, .visionOS, .androidVR:
            return true
        // TV serves no stream URLs at all — SABR is its only delivery.
        case .progressive, .mwebPot, .tv:
            return false
        }
    }

    var sourceKind: VideoSourceKind {
        switch self {
        case .auto:
            return .auto
        case .visionOS:
            return .visionOS
        case .androidVR:
            return .androidVR
        case .progressive:
            return .progressive
        case .mwebPot:
            return .mwebPot
        case .tv:
            return .tv
        }
    }
}

// MARK: - StreamDeliveryPreference

/// How playback should fetch its bytes, when the user wants a say.
///
/// `auto` is the shipping behaviour: the source picks per response — byte
/// ranges while formats carry URLs, SABR when they do not, each falling back
/// to the other. The explicit options pin one delivery and disable the
/// fallback, which is what makes them useful for testing: a failure stays a
/// failure instead of being papered over.
enum StreamDeliveryPreference: String, CaseIterable {
    case automatic = "auto"
    case byteRange = "range"
    case sabrOnly = "sabr"

    static var selected: StreamDeliveryPreference {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.Debug.streamDelivery)
            .flatMap(StreamDeliveryPreference.init) ?? .automatic
    }

    var displayName: String {
        switch self {
        case .automatic:
            return "Auto (by response)"
        case .byteRange:
            return "Byte ranges only"
        case .sabrOnly:
            return "SABR only"
        }
    }
}
