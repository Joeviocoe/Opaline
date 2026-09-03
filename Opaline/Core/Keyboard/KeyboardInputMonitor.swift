import UIKit

/// Tracks whether the user is typing, so plain-letter commands can stand down.
///
/// There is exactly one text-entry surface in the app — the search bar. Its
/// internal `UISearchBarTextField` *is* a `UITextField` subclass, so it posts
/// the ordinary begin/end-editing notifications; watching those avoids both
/// `searchTextField` (iOS 13) and a view-hierarchy walk, and costs a single
/// `Bool` read per keystroke.
///
/// Whether this is load-bearing or merely defensive is a device question:
/// UIKit may already suppress modifier-less commands during text entry. It is
/// cheap either way, and being wrong in the other direction means typing "j"
/// into the search field seeks the player.
final class KeyboardInputMonitor {
    static let shared = KeyboardInputMonitor()

    private(set) var isEditingText = false

    private init() {
        let center = NotificationCenter.default
        let began: [NSNotification.Name] = [
            UITextField.textDidBeginEditingNotification,
            UITextView.textDidBeginEditingNotification
        ]
        let ended: [NSNotification.Name] = [
            UITextField.textDidEndEditingNotification,
            UITextView.textDidEndEditingNotification
        ]
        for name in began {
            center.addObserver(
                self,
                selector: #selector(self.editingDidBegin),
                name: name,
                object: nil
            )
        }
        for name in ended {
            center.addObserver(
                self,
                selector: #selector(self.editingDidEnd),
                name: name,
                object: nil
            )
        }
    }

    /// True when a modal is up anywhere above `responder`. Shortcuts must not
    /// fire underneath a Settings sheet or an action menu, and those screens
    /// are presented rather than pushed, so they never reach the focus
    /// installer either.
    static func isPresentingModally(_ responder: UIViewController?) -> Bool {
        var current = responder
        while let viewController = current {
            if viewController.presentedViewController != nil {
                return true
            }
            current = viewController.parent
        }
        return false
    }

    @objc
    private func editingDidBegin() {
        isEditingText = true
        KeyboardDiagnostics.log("text editing began")
    }

    @objc
    private func editingDidEnd() {
        isEditingText = false
        KeyboardDiagnostics.log("text editing ended")
    }
}
