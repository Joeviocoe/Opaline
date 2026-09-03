import UIKit

/// Search is the one screen where the keyboard has to move between a text
/// field and a list, so it owns more of its key handling than the others.
///
/// The single table shows recent searches while the field is empty and results
/// once a query runs (`setPanel(.history)` / `.results`), so one pair of
/// bindings covers both: Down leaves the field for the list, Up at the top of
/// the list returns to the field.
///
/// No `listFocusVideo(at:)` override — results rows dequeue
/// `SubscriptionVideoCell`, which conforms to `FocusableVideoCell`, and
/// history/suggestion rows are a plain `UITableViewCell`, which does not.
/// `ListFocusHost`'s generic default already tells the two apart correctly
/// by asking whichever cell is actually on screen, with no need to check
/// `panelMode` here at all.
extension SearchViewController: ListFocusHost {
    override var keyCommands: [UIKeyCommand]? {
        // Ask the search bar directly rather than the global editing flag: the
        // flag is driven by notifications, so it can lag the first keypress
        // after the field takes focus, and a missed Down here reads as "the
        // arrow keys do not reach the text box at all".
        guard searchBar.isFirstResponder else {
            return nil
        }
        return Self.editingCommands
    }

    /// Up on the first row hands the chain back to the field, which is what
    /// makes the two halves of this screen feel like one list.
    ///
    /// No `!searchBar.isFirstResponder` guard: there is no scenario where
    /// declining this request is correct, and `UISearchBar.isFirstResponder`
    /// proxies through an internal `UISearchBarTextField` -- if it does not
    /// reliably flip back to false after `resignFirstResponder()` on this
    /// iOS version, a guard here would silently and permanently block every
    /// request after the first field->list trip. becomeFirstResponder() on
    /// an already-focused field is a harmless no-op either way.
    ///
    /// This override was unreachable through every earlier build: it only
    /// took effect once `listFocusDidReachTop()` became a protocol
    /// *requirement* rather than an extension-only default — see the note on
    /// `ListFocusHost` for why that distinction is what made it dispatch at
    /// all.
    func listFocusDidReachTop() -> Bool {
        let accepted = searchBar.becomeFirstResponder()
        KeyboardDiagnostics.logResponder("search: focus -> field", searchBar, accepted: accepted)
        return true
    }

    @objc
    func keyboardFocusList() {
        KeyboardDiagnostics.logTimed("search: field -> list")
        leaveField()
    }

    @objc
    func keyboardLeaveField() {
        KeyboardDiagnostics.logTimed("search: dismiss field")
        leaveField()
    }

    /// Resigning alone is not enough. The coordinator normally hands the chain
    /// back when the software keyboard hides — but with a hardware keyboard
    /// attached there is no software keyboard, so that notification never
    /// arrives and the chain would be left with no owner and every command
    /// dead. Ask for it explicitly instead of relying on the side effect.
    private func leaveField() {
        searchBar.resignFirstResponder()
        KeyboardFocusCoordinator.shared.reassert()
    }
}

private extension SearchViewController {
    /// Down drops into the list; Escape and Backspace give the field up without
    /// leaving the screen. Resigning is enough to move the chain — the ring
    /// re-asserts itself through the coordinator's keyboard-hide observer.
    static let editingCommands: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.downArrow,
            action: #selector(SearchViewController.keyboardFocusList)
        ),
        KeyCommandInput.command(
            KeyCommandInput.escape,
            action: #selector(SearchViewController.keyboardLeaveField)
        )
    ]
}
