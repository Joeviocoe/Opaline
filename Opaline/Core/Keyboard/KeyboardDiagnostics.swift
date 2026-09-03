import UIKit

/// Instrumentation for the one device session that answers everything this
/// branch could not settle statically: whether modifier-less commands arrive,
/// whether a 1x1 ring is allowed to be first responder, which route the
/// keyboard's media keys take, what the real auto-repeat interval is, and
/// whether a deeper responder really does shadow a shallower one.
///
/// The whole thing compiles away when `LEGACY_IOS9` is not defined — the
/// `@autoclosure` means call sites cost nothing on `main`, so they can be
/// written unconditionally rather than smeared with `#if`.
enum KeyboardDiagnostics {
    /// Wall-clock of the previous logged key event, for the inter-event delta
    /// that measures auto-repeat. Main-thread only, like every key event.
    private static var lastEventAt: CFTimeInterval = 0

    static func log(_ message: @autoclosure () -> String) {
        #if LEGACY_IOS9
        AppLog.keys(message())
        #endif
    }

    /// Logs an event together with the gap since the previous one. That gap is
    /// the measurement the seek-escalation window depends on: a held key
    /// auto-repeats, and on iOS 9 a `UIKeyCommand` carries no press phase, so
    /// a repeat is indistinguishable from a fast tap except by its timing.
    static func logTimed(_ message: @autoclosure () -> String) {
        #if LEGACY_IOS9
        let now = CACurrentMediaTime()
        let delta = lastEventAt > 0 ? (now - lastEventAt) * 1_000 : -1
        lastEventAt = now
        let gap = delta < 0 ? "first" : String(format: "%.0fms", delta)
        AppLog.keys("\(message()) [+\(gap)]")
        #endif
    }

    static func logResponder(
        _ what: String,
        _ owner: AnyObject,
        accepted: Bool
    ) {
        #if LEGACY_IOS9
        AppLog.keys(
            "\(what) \(type(of: owner)) -> \(accepted ? "YES" : "NO")"
        )
        #endif
    }
}
