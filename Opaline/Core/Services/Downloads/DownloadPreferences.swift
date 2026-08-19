import Foundation

/// What a download brings with it. Kept apart from the playback quality
/// setting: what someone watches on wifi and what they want sitting on the
/// device are different decisions.
enum DownloadPreferences {
    /// Raw values are what lands in UserDefaults, so they are spelled out
    /// rather than derived from the case names.
    enum CommentsMode: String, CaseIterable {
        case none = "off"
        case top = "top_comments"
        case newest = "newest_comments"

        var displayName: String {
            switch self {
            case .none:
                return "downloads.comments.none".localized
            case .top:
                return "downloads.comments.top".localized
            case .newest:
                return "downloads.comments.newest".localized
            }
        }
    }

    /// Stored constant, never localized — only its display is translated,
    /// the same way the playback quality setting works.
    static let askEveryTime = "Ask"

    static var qualityOptions: [String] {
        [askEveryTime, "1080p", "720p", "480p", "360p"]
    }

    static var quality: String {
        get {
            UserDefaults.standard.string(
                forKey: UserDefaultsKeys.Downloads.quality
            ) ?? askEveryTime
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Downloads.quality
            )
        }
    }

    static var qualityDisplayName: String {
        quality == askEveryTime
            ? "downloads.quality.ask".localized
            : quality
    }

    /// nil means "ask" — there is no preferred height to match against.
    static var preferredHeight: Int? {
        ["1080p": 1_080, "720p": 720, "480p": 480, "360p": 360][quality]
    }

    static var comments: CommentsMode {
        get { read(UserDefaultsKeys.Downloads.comments) ?? .top }
        set { write(newValue, UserDefaultsKeys.Downloads.comments) }
    }

    /// Which subtitle languages a download brings, as language codes.
    /// Empty means none — there is no separate "off" switch, because "no
    /// languages selected" already says it.
    static var captionLanguages: Set<String> {
        get {
            guard let stored = UserDefaults.standard.stringArray(
                forKey: UserDefaultsKeys.Downloads.captions
            ) else {
                return [AppLanguage.effective.rawValue]
            }
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(
                Array(newValue).sorted(),
                forKey: UserDefaultsKeys.Downloads.captions
            )
        }
    }

    /// "Russian, English" while the list is short, a count once it is not.
    static var captionsDisplayName: String {
        let picked = AppLanguage.allCases.filter {
            captionLanguages.contains($0.rawValue)
        }
        guard !picked.isEmpty else {
            return "downloads.captions.none".localized
        }
        guard picked.count <= 2 else {
            return "downloads.captions.count".localized(with: "\(picked.count)")
        }
        return picked.map(\.displayName).joined(separator: ", ")
    }

    private static func read<T: RawRepresentable>(
        _ key: String
    ) -> T? where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:))
    }

    private static func write<T: RawRepresentable>(
        _ value: T, _ key: String
    ) where T.RawValue == String {
        UserDefaults.standard.set(value.rawValue, forKey: key)
    }
}
