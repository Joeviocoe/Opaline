import ObjectiveC
import UIKit

/// Keyboard navigation between the channel-filter avatar bar and the video
/// list below it, and Backspace/Esc clearing the active filter from anywhere
/// on the screen.
///
/// A second, independent `ListFocusController` drives the bar itself --
/// `.row` axis, pointed at `channelBar.collectionView` -- reusing everything
/// `ListFocusController` already does (movement, reveal, Return activating
/// exactly like a tap, via `focusSelect` calling the bar's own
/// `didSelectItemAt`) rather than building a parallel mechanism for what is
/// already exactly the shape it handles.
///
/// Neither ring's own `didMoveToWindow` fires when focus moves between the
/// two: both stay in the window the whole time, since this is a handoff
/// within one screen, not a navigation push. So both directions are
/// explicit: `listFocusDidReachTop()` (a `ListFocusHost` requirement,
/// correctly witness-dispatched -- see the note on `ListFocusHost` for why
/// that distinction is load-bearing) claims the bar on Up from row 0, and a
/// dedicated Down binding here claims the list back. The Down binding is
/// declared unconditionally rather than gated on which ring is focused --
/// a deeper responder always wins a duplicate input, so this only ever
/// actually fires when the list's own Down, which its ring declares, is not
/// already in the chain, i.e. exactly when the bar has it instead.
private var channelBarFocusKey: UInt8 = 0

extension SubscriptionsViewController {
    private var channelBarFocus: ListFocusController {
        if let existing = objc_getAssociatedObject(self, &channelBarFocusKey)
            as? ListFocusController {
            return existing
        }
        let controller = ListFocusController(axis: .row, geometry: channelBar.collectionView)
        objc_setAssociatedObject(
            self,
            &channelBarFocusKey,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return controller
    }

    /// Declining (no channels yet) lets `escapeTop()` log the usual "nothing
    /// to do" rather than silently eating the key.
    func listFocusDidReachTop() -> Bool {
        guard channelBarFocus.hasFocusableItem else {
            return false
        }
        channelBarFocus.claimFocus()
        return true
    }

    /// Esc/Backspace on this screen only ever needs to know whether a filter
    /// is active, never which ring (if either) currently has focus --
    /// `exitChannelFilter()` is already a no-op with nothing selected, so an
    /// unconditional binding here would be harmless too, but declaring it
    /// only while a filter is live keeps the screen's own Escape from
    /// shadowing the global one (minimize the player, dismiss a search
    /// push) the rest of the time. One of two pre-built arrays, never
    /// constructed here -- `keyCommands` is consulted on every responder
    /// walk, and `KeyCommandCatalog`'s own discipline is that building an
    /// array there, let alone new `UIKeyCommand` objects, allocates on every
    /// keystroke.
    override var keyCommands: [UIKeyCommand]? {
        selectedChannel != nil ? Self.channelBarDownAndExitFilter : Self.channelBarDownOnly
    }
}

private extension SubscriptionsViewController {
    @objc
    func keyboardChannelBarDown() {
        guard channelBarFocus.focused != nil else {
            return
        }
        KeyboardDiagnostics.log("channel bar: focus -> list")
        ListFocusInstaller.controller(for: self)?.claimFocus()
    }

    @objc
    func keyboardExitChannelFilter() {
        KeyboardDiagnostics.log("channel bar: filter cleared from keyboard")
        exitChannelFilter()
    }

    static let channelBarDownOnly: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.downArrow,
            action: #selector(SubscriptionsViewController.keyboardChannelBarDown)
        )
    ]

    static let channelBarDownAndExitFilter: [UIKeyCommand] = channelBarDownOnly + [
        KeyCommandInput.command(
            KeyCommandInput.escape,
            action: #selector(SubscriptionsViewController.keyboardExitChannelFilter)
        ),
        KeyCommandInput.command(
            KeyCommandInput.backspace,
            action: #selector(SubscriptionsViewController.keyboardExitChannelFilter)
        )
    ]
}
