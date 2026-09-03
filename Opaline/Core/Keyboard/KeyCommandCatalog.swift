import UIKit

/// Every key command in the app, pre-built once.
///
/// `keyCommands` is consulted on each responder walk, so building an array
/// there — or worse concatenating two — would allocate on every keystroke. Each
/// override below returns exactly one of these `static let`s, which is why the
/// state-dependent sets are enumerated as whole arrays rather than composed.
/// `UIKeyCommand` objects are safe to share between responders: dispatch is by
/// selector through the chain, not bound to a target.
///
/// Titles are resolved once at first use, which is correct here because an
/// in-app language change already requires a restart.
enum KeyCommandCatalog {
    /// Establishing focus, before there is any. Arrows only — pressing down on
    /// a fresh feed should start at the top rather than do nothing.
    static let focusListIdle: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.upArrow,
            action: #selector(ListFocusRingView.focusMoveUp)
        ),
        KeyCommandInput.command(
            KeyCommandInput.downArrow,
            action: #selector(ListFocusRingView.focusMoveDown)
        ),
        KeyCommandInput.command(
            KeyCommandInput.tab,
            action: #selector(ListFocusRingView.focusNextSection)
        )
    ]

    static let focusListFocused: [UIKeyCommand] = focusListIdle + focusShared

    /// A grid adds the horizontal pair. A list deliberately never declares
    /// them, which is how the player keeps the arrow keys for seeking while a
    /// single-column list is on screen.
    static let focusGridIdle: [UIKeyCommand] = focusListIdle + [
        KeyCommandInput.command(
            KeyCommandInput.leftArrow,
            action: #selector(ListFocusRingView.focusMoveLeft)
        ),
        KeyCommandInput.command(
            KeyCommandInput.rightArrow,
            action: #selector(ListFocusRingView.focusMoveRight)
        )
    ]

    static let focusGridFocused: [UIKeyCommand] = focusGridIdle + focusShared

    /// While a text field holds the chain, only modified commands survive —
    /// otherwise typing "j" into the search bar seeks the player.
    // Backspace is deliberately absent here: while a text field has the chain
    // it must delete a character, not dismiss the player.
    static let textEntry: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.escape,
            action: #selector(RootContainerViewController.keyboardEscape)
        )
    ] + tabCommands

    static let global: [UIKeyCommand] = tabCommands + [
        KeyCommandInput.command(
            KeyCommandInput.slash,
            action: #selector(RootContainerViewController.keyboardOpenSearch),
            titleKey: "keyboard.search"
        ),
        KeyCommandInput.command(
            "f",
            action: #selector(RootContainerViewController.keyboardOpenSearch),
            modifiers: .command
        ),
        // Three ways in, because which one a person reaches for depends on the
        // keyboard: "/" is the muscle memory, Command-F the platform habit, and
        // Command-slash what a folio keyboard without a dedicated key invites.
        KeyCommandInput.command(
            KeyCommandInput.slash,
            action: #selector(RootContainerViewController.keyboardOpenSearch),
            modifiers: .command
        ),
        KeyCommandInput.command(
            KeyCommandInput.space,
            action: #selector(RootContainerViewController.keyboardTogglePlayback),
            titleKey: "keyboard.playPause"
        ),
        KeyCommandInput.command(
            "k",
            action: #selector(RootContainerViewController.keyboardTogglePlayback)
        ),
        KeyCommandInput.command(
            "f",
            action: #selector(RootContainerViewController.keyboardRestoreOrFullscreen),
            titleKey: "keyboard.fullscreen"
        ),
        KeyCommandInput.command(
            "x",
            action: #selector(RootContainerViewController.keyboardStopPlayer),
            titleKey: "keyboard.stop"
        ),
        KeyCommandInput.command(
            KeyCommandInput.escape,
            action: #selector(RootContainerViewController.keyboardEscape),
            titleKey: "keyboard.close"
        ),
        KeyCommandInput.command(
            KeyCommandInput.backspace,
            action: #selector(RootContainerViewController.keyboardEscape)
        )
    ]

    static func focus(
        axis: ListFocusController.Axis,
        hasFocus: Bool
    ) -> [UIKeyCommand] {
        if axis == .grid {
            return hasFocus ? focusGridFocused : focusGridIdle
        }
        return hasFocus ? focusListFocused : focusListIdle
    }
}

// MARK: - Pieces

private extension KeyCommandCatalog {
    /// Everything that only makes sense once something is focused.
    static let focusShared: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.enter,
            action: #selector(ListFocusRingView.focusActivate),
            titleKey: "keyboard.open"
        ),
        KeyCommandInput.command(
            KeyCommandInput.tab,
            action: #selector(ListFocusRingView.focusPreviousSection),
            modifiers: .shift
        ),
        KeyCommandInput.command(
            KeyCommandInput.upArrow,
            action: #selector(ListFocusRingView.focusJumpToTop),
            modifiers: .command
        ),
        KeyCommandInput.command(
            KeyCommandInput.downArrow,
            action: #selector(ListFocusRingView.focusJumpToBottom),
            modifiers: .command
        ),
        KeyCommandInput.command(
            "q",
            action: #selector(ListFocusRingView.focusQueue),
            titleKey: "keyboard.queue"
        ),
        KeyCommandInput.command(
            KeyCommandInput.pageUp,
            action: #selector(ListFocusRingView.focusPageUp)
        ),
        KeyCommandInput.command(
            KeyCommandInput.pageDown,
            action: #selector(ListFocusRingView.focusPageDown)
        )
    ]

    /// Tabs are addressed by visible position, not by `DefaultTab.tabTag`: the
    /// Shorts tab is optional, and the bar renumbers itself when it is off.
    /// For the same reason only the first two are named in the HUD — what
    /// tabs 3 and 4 are depends on a setting.
    static let tabCommands: [UIKeyCommand] = [
        KeyCommandInput.command(
            "1",
            action: #selector(RootContainerViewController.keyboardSelectTab1),
            modifiers: .command,
            titleKey: "keyboard.tab1"
        ),
        KeyCommandInput.command(
            "2",
            action: #selector(RootContainerViewController.keyboardSelectTab2),
            modifiers: .command,
            titleKey: "keyboard.tab2"
        ),
        KeyCommandInput.command(
            "3",
            action: #selector(RootContainerViewController.keyboardSelectTab3),
            modifiers: .command
        ),
        KeyCommandInput.command(
            "4",
            action: #selector(RootContainerViewController.keyboardSelectTab4),
            modifiers: .command
        )
    ]
}
