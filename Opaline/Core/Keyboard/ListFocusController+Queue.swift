import UIKit

/// Queueing from a list, the index-path formatter every focus log line
/// uses, and escapeTop() -- all here only to keep the controller inside the
/// 300-line file limit the linter enforces. escapeTop() cannot stay `private`
/// once it lives in a different file from its callers (move(),
/// establishFocus()): Swift's same-file cross-extension private sharing
/// does not extend across files, so it is internal here instead.
extension ListFocusController {
    /// Adds the focused video to the play queue — or, if nothing is playing
    /// at all, starts it, minimized.
    ///
    /// The guards are deliberately separate: a single combined `guard` logged
    /// "nothing focused to queue" for three different causes, which on device
    /// was indistinguishable from the key not working at all.
    func queueFocused() {
        guard let focused = focused else {
            KeyboardDiagnostics.log("queue: no focus")
            return
        }
        guard let host = focusHost else {
            KeyboardDiagnostics.log("queue: host gone")
            return
        }
        guard let video = host.listFocusVideo(at: focused) else {
            KeyboardDiagnostics.log(
                "queue: \(type(of: host)) has no video at " +
                "\(focused.section).\(focused.item)"
            )
            return
        }
        guard let current = VideoRouter.shared.currentVideo else {
            playDirectly(video, presentingFrom: host)
            return
        }
        appendToQueue(video, current: current)
    }

    /// Nothing playing at all: there is no queue panel to reach until
    /// something is playing anyway, so q replicates the one thing that
    /// always works -- opening the video, same as a tap -- but stays
    /// minimized, since the point of queueing from a list is to keep
    /// browsing, not to be dropped into full screen.
    private func playDirectly(_ video: Video, presentingFrom host: ListFocusHost) {
        KeyboardDiagnostics.logTimed("queue: nothing playing, opening \(video.id) minimized")
        VideoRouter.shared.open(video: video, from: host, startsExpanded: false)
    }

    /// The video already playing may not itself be a queue member -- most
    /// often because it got there through `playDirectly` above, which plays
    /// rather than queues. Anchor it at position 0 before the first real
    /// append, or `currentIndex` (unmoved by `append`) is left pointing at
    /// the first *queued* item instead of what is actually playing, and
    /// Next/Previous walk the wrong videos.
    private func appendToQueue(_ video: Video, current: Video) {
        if PlaybackQueue.shared.videos.isEmpty {
            PlaybackQueue.shared.append([current])
        }
        PlaybackQueue.shared.append([video])
        let total = PlaybackQueue.shared.videos.count
        KeyboardDiagnostics.logTimed("queue += \(video.id) (\(total) total)")
        // Queueing changes nothing on screen, so without this the key looks dead.
        KeyboardToast.show(
            "keyboard.toast.queued".localized(with: total),
            over: ringHostView
        )
    }

    /// `section.item`, or "none".
    func describe(_ indexPath: IndexPath?) -> String {
        guard let indexPath = indexPath else {
            return "none"
        }
        return "\(indexPath.section).\(indexPath.item)"
    }

    /// Up at the topmost item: offer it to the screen before swallowing it.
    ///
    /// Logs the decline too, not just the success -- a silent `false` here
    /// was indistinguishable on device from "this code path never ran at
    /// all", which cost a whole round trip to even confirm move() was
    /// calling this rather than something else being wrong.
    func escapeTop() -> Bool {
        guard let host = focusHost else {
            KeyboardDiagnostics.log("focus at top: host is gone")
            return false
        }
        guard host.listFocusDidReachTop() else {
            KeyboardDiagnostics.log("focus at top: \(type(of: host)) declined")
            return false
        }
        KeyboardDiagnostics.log("focus left the top, screen took the chain")
        return true
    }
}
