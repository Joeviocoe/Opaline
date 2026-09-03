import MediaPlayer
import UIKit

/// The second input route, for keys `UIKeyCommand` cannot see.
///
/// A keyboard's media keys reach an app one of two ways: as HID
/// consumer-control usages, which surface through `MPRemoteCommandCenter`, or
/// as ordinary presses through the responder chain. Opaline already handles the
/// first (`NowPlayingService`), and remote commands only arrive when the app
/// owns the Now Playing session — active audio session, populated now-playing
/// info — which is why a media key does nothing outside playback.
///
/// The second route is reachable on iOS 9 after all. `UIPress.key`, which names
/// a *character* key, is iOS 13.4 — but `UIPressType` itself is
/// `API_AVAILABLE(ios(9.0))` and its cases include `.playPause`, `.select` and
/// `.menu`. So a keyboard sending media keys as presses can be served here.
///
/// Both routes are live, so a keyboard that emits both kinds would toggle
/// twice. `claimPress` is the guard against that: whichever route arrives
/// first wins, and the other is dropped for `dedupeWindow`.
enum PressTypeResponder {
    /// Long enough to cover the two routes racing for the same physical press,
    /// short enough never to swallow a deliberate second press.
    private static let dedupeWindow: CFTimeInterval = 0.3

    private static var lastHandledAt: CFTimeInterval = 0

    /// Called by both routes. Returns false when this press has already been
    /// serviced by the other one.
    static func claimPress(source: String) -> Bool {
        let now = CACurrentMediaTime()
        if now - lastHandledAt < dedupeWindow {
            KeyboardDiagnostics.log("press \(source) DROPPED (deduped)")
            return false
        }
        lastHandledAt = now
        KeyboardDiagnostics.log("press \(source) claimed")
        return true
    }

    /// Logs every press type seen, including the ones nothing acts on, so one
    /// device session settles which route this keyboard actually uses.
    static func describe(_ press: UIPress) -> String {
        let names: [Int: String] = [
            0: "upArrow", 1: "downArrow", 2: "leftArrow", 3: "rightArrow",
            4: "select", 5: "menu", 6: "playPause"
        ]
        let raw = press.type.rawValue
        let name = names[raw] ?? "unknown"
        return "\(name)(\(raw)) phase=\(press.phase.rawValue)"
    }
}
