import Foundation
import QuartzCore

#if LEGACY_IOS9
/// Milestones from tapping play to seeing a picture.
///
/// Every metric before this one measured the port's internals — "composition
/// ready at 9.4s" — while the user was waiting 40 seconds and then looking at a
/// black rectangle with sound. Those are different questions, and only this one
/// matters. Each milestone is stamped from the same origin so the gaps between
/// them say which stage is actually costing the time.
///
/// `firstFrame` is the honest number: `AVPlayerLayer.isReadyForDisplay`, i.e.
/// the moment a picture exists. `audible` is when audio starts, so "sound but
/// no video" shows up as a gap between them rather than as a bug report.
enum LegacyPlaybackTimeline {
    private static var origin: CFTimeInterval = 0
    private static var seen: Set<String> = []
    private static let lock = NSLock()

    /// Called when the user asks for a video.
    static func begin(_ videoId: String) {
        lock.lock()
        origin = CACurrentMediaTime()
        seen = []
        lock.unlock()
        AppLog.player("timeline: ---- play tapped (\(videoId)) ----")
    }

    /// Records a milestone once per playback. Repeats are ignored, so an
    /// observer that fires repeatedly does not flood the log.
    static func mark(_ name: String, detail: String? = nil) {
        lock.lock()
        if origin == 0 || seen.contains(name) {
            lock.unlock()
            return
        }
        seen.insert(name)
        let elapsed = CACurrentMediaTime() - origin
        lock.unlock()
        AppLog.player(
            "timeline: +\(String(format: "%.1f", elapsed))s \(name)"
                + (detail.map { " — \($0)" } ?? "")
        )
    }

    /// Reports a milestone that may legitimately happen more than once.
    static func note(_ name: String) {
        lock.lock()
        let elapsed = origin == 0 ? 0 : CACurrentMediaTime() - origin
        lock.unlock()
        AppLog.player("timeline: +\(String(format: "%.1f", elapsed))s \(name)")
    }
}
#endif
