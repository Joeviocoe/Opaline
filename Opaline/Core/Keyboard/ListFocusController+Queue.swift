import UIKit

/// Queueing from a list, the index-path formatter every focus log line
/// uses, escapeTop(), the claimFocus()/hasFocusableItem pair a same-screen
/// handoff uses (the subscriptions channel bar and its video list), and
/// target() itself -- all here only to keep the controller inside the
/// 300-line file limit the linter enforces. escapeTop() and setFocus()
/// cannot stay `private` once they are called from a different file than
/// move() / establishFocus(): Swift's same-file cross-extension private
/// sharing does not extend across files, so they are internal instead.
extension ListFocusController {
    func target(
        from current: IndexPath,
        direction: FocusDirection,
        geometry: FocusGeometry
    ) -> IndexPath? {
        let vertical = direction == .up || direction == .down
        if axis == .list {
            guard vertical else {
                return nil
            }
            return ListFocusSearch.step(
                from: current,
                forward: direction == .down,
                geometry: geometry
            )
        }
        // A single row has nothing to step to vertically -- claiming only the
        // geometric search, with no step() fallback, is what makes an
        // unclaimed Down fall through the chain instead of silently landing
        // on whichever avatar sits "below" in flattened order.
        if axis == .row {
            guard !vertical else {
                return nil
            }
            return ListFocusSearch.next(from: current, direction: direction, geometry: geometry)
        }
        if let found = ListFocusSearch.next(
            from: current,
            direction: direction,
            geometry: geometry
        ) {
            return found
        }
        guard vertical else {
            return nil
        }
        return ListFocusSearch.step(
            from: current,
            forward: direction == .down,
            geometry: geometry
        )
    }

    /// Whether there is anything at all to focus. A handoff should only
    /// claim the chain if it would actually land somewhere -- an empty
    /// channel bar must not swallow Up and go nowhere.
    var hasFocusableItem: Bool {
        geometry?.firstFocusableIndexPath() != nil
    }

    /// Explicitly takes the responder chain, establishing focus at the first
    /// item if nothing is already focused. For a handoff between two regions
    /// on one screen, where neither ring's own `didMoveToWindow` fires,
    /// since nothing here ever actually leaves the window.
    func claimFocus() {
        guard let geometry = geometry else {
            return
        }
        if focused == nil {
            setFocus(geometry.firstFocusableIndexPath(), animated: false)
        }
        let accepted = ring.becomeFirstResponder()
        KeyboardDiagnostics.logResponder("focus claimed", ring, accepted: accepted)
    }

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
    /// something is playing anyway, so q replicates the touchscreen path
    /// precisely -- the "..." menu's own add-to-queue opens the video same
    /// as a tap would, full screen, and leaves minimizing to a second,
    /// separate action. Here that second step is automatic instead of a
    /// chevron tap, but it still only happens once the open has genuinely
    /// finished -- collapsing in the same breath as expand is what raced
    /// the first-responder handoff and left the arrows controlling player
    /// volume instead of list focus.
    private func playDirectly(_ video: Video, presentingFrom host: ListFocusHost) {
        KeyboardDiagnostics.logTimed("queue: nothing playing, opening \(video.id)")
        VideoRouter.shared.open(video: video, from: host) {
            KeyboardDiagnostics.logTimed("queue: \(video.id) expanded, minimizing")
            VideoRouter.shared.minimize()
        }
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
