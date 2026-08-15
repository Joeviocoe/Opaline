import Foundation

/// Narrates what resolving a stream is currently doing.
///
/// Resolving is not one step: it can try a client, be refused, renew the
/// visitor identity, fall back to another source, solve signatures remotely and
/// open a SABR session — and until now all of that hid behind a single
/// "Resolving stream…". When it takes ten seconds or fails, the difference
/// between "renewing identity, attempt 3" and "solving signatures" is the whole
/// story.
///
/// A plain closure rather than notifications: there is exactly one player on
/// screen, and it owns the label.
enum PlaybackProgress {
    /// Set by `PlaybackFacade` while a resolve is in flight, cleared after.
    static var report: ((String) -> Void)?

    static func step(_ key: String) {
        report?(key.localized)
    }

    /// For steps that count, like identity re-draws.
    static func step(_ key: String, _ argument: CVarArg) {
        report?(key.localized(with: argument))
    }
}
