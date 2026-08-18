import Foundation

/// The client playback nonce — YouTube's per-playback id, 16 characters of its
/// own alphabet. Watchtime pings carry it as `cpn`, and so does every
/// googlevideo request a television makes; without it SABR media is refused.
enum PlaybackNonce {
    private static let alphabet = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    static func make() -> String {
        String((0 ..< 16).compactMap { _ in alphabet.randomElement() })
    }
}
