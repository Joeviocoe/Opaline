import UIKit

/// Queueing from a list, plus the index-path formatter every focus log line
/// uses — both here only to keep the controller inside the 300-line file
/// limit the linter enforces.
extension ListFocusController {
    /// Adds the focused video to the play queue.
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
        PlaybackQueue.shared.append([video])
        KeyboardDiagnostics.logTimed("queue += \(video.id)")
        // Queueing changes nothing on screen, so without this the key looks dead.
        KeyboardToast.show("keyboard.toast.queued".localized, over: ringHostView)
    }

    /// `section.item`, or "none".
    func describe(_ indexPath: IndexPath?) -> String {
        guard let indexPath = indexPath else {
            return "none"
        }
        return "\(indexPath.section).\(indexPath.item)"
    }
}
