import Foundation

/// The user's playback chain: which steps are on, and in what order.
///
/// Playback used to pick sources by a hardcoded ladder, and every time YouTube
/// moved, the ladder was wrong in a way only a release could fix. This is the
/// same decision expressed as data, so it can be reordered on the device.
enum PlaybackChainSettings {
    /// VisionOS first, both of its steps: it is the client googlevideo lets
    /// play past the anonymous one-minute cut-off, and TV needs an account
    /// to run at all.
    static let defaultOrder = [
        "visionos.range", "visionos.sabr", "tv.sabr", "progressive"
    ]
    /// Everything is on by default: a step that cannot run (TV without an
    /// account) already skips itself.
    static let defaultEnabled = defaultOrder

    static var order: [String] {
        get {
            let stored = UserDefaults.standard
                .stringArray(forKey: UserDefaultsKeys.Debug.playbackChainOrder)
            guard let stored, !stored.isEmpty else {
                return defaultOrder
            }
            // A step added by a later version is unknown to the stored order;
            // append it rather than dropping it silently.
            return stored + defaultOrder.filter { !stored.contains($0) }
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: UserDefaultsKeys.Debug.playbackChainOrder
            )
        }
    }

    static var enabled: Set<String> {
        get {
            let stored = UserDefaults.standard
                .stringArray(forKey: UserDefaultsKeys.Debug.playbackChainEnabled)
            guard let stored else {
                return Set(defaultEnabled)
            }
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(
                Array(newValue), forKey: UserDefaultsKeys.Debug.playbackChainEnabled
            )
        }
    }

    /// The steps to try, in order: enabled, and possible for this session.
    static func activeSteps(
        from registry: PlaybackStepRegistry = .default,
        isSignedIn: Bool = OAuthClient.shared.isSignedIn
    ) -> [PlaybackStep] {
        let on = enabled
        return order
            .compactMap { registry.step(id: $0) }
            .filter { on.contains($0.id) }
            .filter { isSignedIn || !$0.requiresSignIn }
    }
}
