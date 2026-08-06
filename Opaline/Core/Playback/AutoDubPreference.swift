import Foundation

/// "Start videos dubbed" policy: when a video's original audio language
/// differs from the preferred one and a matching dub exists, playback starts
/// (or switches) on that dub. Sources consult it at build time; the player
/// shell consults it when tracks arrive from a background probe.
enum AutoDubPreference {
    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.AutoDub.enabled
            ) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.AutoDub.enabled
            )
        }
    }

    /// AI auto-dubs (`.10` tracks) never auto-picked when on.
    static var ignoreAIDubs: Bool {
        get {
            UserDefaults.standard.object(
                forKey: UserDefaultsKeys.AutoDub.ignoreAIDubs
            ) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.AutoDub.ignoreAIDubs
            )
        }
    }

    /// Explicit dub language code, nil = follow the app language (which
    /// itself defaults to the system language).
    static var languageOverride: String? {
        get {
            UserDefaults.standard.string(
                forKey: UserDefaultsKeys.AutoDub.language
            )
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.AutoDub.language
            )
        }
    }

    /// Base language code the dub should match, e.g. "ru".
    static var effectiveLanguageCode: String {
        baseCode(languageOverride ?? AppLanguage.effective.rawValue)
    }

    /// The dub to start on, or nil to keep the video's default track —
    /// disabled, single-audio, original already in the preferred language,
    /// or no acceptable dub for it.
    static func autoDubTrack(in tracks: [AudioTrack]) -> AudioTrack? {
        guard isEnabled, tracks.count > 1,
              let original = tracks.first(where: { $0.isOriginal }) else {
            return nil
        }
        let language = effectiveLanguageCode
        guard original.languageCode != language else {
            return nil
        }
        let dubs = tracks.filter {
            !$0.isOriginal && $0.languageCode == language
        }
        if let human = dubs.first(where: { !$0.isAutoDubbed }) {
            return human
        }
        return ignoreAIDubs ? nil : dubs.first
    }

    /// "pt-BR" → "pt", "zh-Hans" → "zh".
    private static func baseCode(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init) ?? code
    }
}

extension AudioTrack {
    /// Base language code from the track id ("ru.3" → "ru", "pt-BR.10" →
    /// "pt") — the id is the only language-stable field; `displayName` is
    /// localized to the request `hl`.
    var languageCode: String {
        let tag = id.split(separator: ".").first.map(String.init) ?? id
        return (tag.split(separator: "-").first.map(String.init) ?? tag)
            .lowercased()
    }
}

extension Notification.Name {
    /// Posted (main thread, object = the source) when a source learns its
    /// audio tracks only after playback already started — the composite's
    /// background dub probe. Lets the shell apply [[AutoDubPreference]].
    static let sourceAudioTracksDidChange = Notification.Name(
        "VideoSourceAudioTracksDidChange"
    )
}
