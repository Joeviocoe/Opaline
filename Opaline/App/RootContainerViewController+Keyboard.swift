import UIKit

/// The app-wide commands, and the floor of the responder chain.
///
/// They live here rather than on `MainTabBarController` for a structural
/// reason. With a tab on screen the chain runs
/// `... -> MainTabBarController -> RootContainer -> window`, but while the
/// player panel is expanded it runs
/// `WatchVC -> wrapper -> PlayerPanel -> RootContainer -> window` — and the tab
/// bar controller is not in it at all, because the panel is parented here
/// rather than to the tab bar (issue #30, explained at the top of the main
/// file). This controller is the only object present in both, which is exactly
/// when transport shortcuts matter most.
extension RootContainerViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        if KeyboardInputMonitor.shared.isEditingText {
            return KeyCommandCatalog.textEntry
        }
        if KeyboardInputMonitor.isPresentingModally(self) {
            return nil
        }
        return KeyCommandCatalog.global
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        KeyboardFocusCoordinator.shared.install(root: self)
    }

    /// Media keys when the player is not expanded — the watch screen handles
    /// its own; see the note there.
    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {
        var handled = false
        for press in presses {
            KeyboardDiagnostics.logTimed("press \(PressTypeResponder.describe(press))")
            guard press.type == .playPause else {
                continue
            }
            if PressTypeResponder.claimPress(source: "UIPress/root") {
                keyboardTogglePlayback()
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    var playerPanel: PlayerPanelViewController? {
        children.compactMap { $0 as? PlayerPanelViewController }.first
    }
}

// MARK: - Actions

extension RootContainerViewController {
    @objc
    func keyboardSelectTab1() { selectTab(at: 0) }

    @objc
    func keyboardSelectTab2() { selectTab(at: 1) }

    @objc
    func keyboardSelectTab3() { selectTab(at: 2) }

    @objc
    func keyboardSelectTab4() { selectTab(at: 3) }

    /// `toolbarOpenSearch()` pushes onto `self.navigationController` — and a
    /// navigation controller's own `navigationController` is nil. Calling it on
    /// `selectedViewController` (which *is* the nav controller) therefore built
    /// the search screen and silently dropped it: the command logged, nothing
    /// appeared. Ask the visible screen instead.
    @objc
    func keyboardOpenSearch() {
        let selected = mainTabBar.selectedViewController
        let target = (selected as? UINavigationController)?.visibleViewController
            ?? selected
        let name = target.map { String(describing: type(of: $0)) } ?? "nil"
        KeyboardDiagnostics.logTimed("open search on \(name)")
        target?.toolbarOpenSearch()
    }

    /// Reaches the minimised player. When the panel is expanded the watch
    /// screen is first responder and gets `space` before this ever runs.
    @objc
    func keyboardTogglePlayback() {
        guard let panel = playerPanel else {
            KeyboardDiagnostics.logTimed("toggle playback: no player")
            return
        }
        KeyboardDiagnostics.logTimed("toggle playback (mini)")
        panel.watchVC.keyboardTogglePlayPause()
    }

    /// Escape minimises the player, and until now nothing brought it back —
    /// the video kept playing with no way in from the keyboard. F restores it
    /// when it is collapsed, and means fullscreen once it is up.
    @objc
    func keyboardRestoreOrFullscreen() {
        guard let panel = playerPanel else {
            KeyboardDiagnostics.logTimed("restore: no player")
            return
        }
        guard panel.isExpanded else {
            KeyboardDiagnostics.logTimed("restore: expanding the mini player")
            VideoRouter.shared.expandPanel()
            return
        }
        KeyboardDiagnostics.logTimed("restore: already up, fullscreen")
        panel.watchVC.keyboardToggleFullscreen()
    }

    /// Stop, as distinct from Escape's minimise. Same end state as tapping the
    /// X on the mini player, from anywhere: leave fullscreen, pause, drop the
    /// queue, and take the panel down. `close()` handles the whole sequence.
    @objc
    func keyboardStopPlayer() {
        guard playerPanel != nil else {
            KeyboardDiagnostics.logTimed("stop: no player")
            return
        }
        KeyboardDiagnostics.logTimed("stop: closing the player")
        VideoRouter.shared.clearCurrentWatch()
    }

    /// Back first, then the player.
    ///
    /// On a pushed screen the top-left chevron is the obvious thing Escape
    /// should do, and it is the only way back from the keyboard. The player
    /// only hears about it when there is nothing to pop — and when the panel is
    /// expanded it never gets this far anyway, because `WatchViewController` is
    /// first responder and its own Escape is deeper in the chain.
    @objc
    func keyboardEscape() {
        if let nav = mainTabBar.selectedViewController as? UINavigationController,
           nav.viewControllers.count > 1 {
            KeyboardDiagnostics.logTimed("escape: back from \(type(of: nav.topViewController))")
            nav.popViewController(animated: true)
            return
        }
        guard let panel = playerPanel else {
            KeyboardDiagnostics.logTimed("escape: nothing to dismiss")
            return
        }
        KeyboardDiagnostics.logTimed("escape (panel)")
        panel.watchVC.keyboardEscape()
    }

    /// Tabs are addressed by visible position: the Shorts tab is optional, so
    /// its `DefaultTab.tabTag` of 3 is not its index when it is switched off.
    private func selectTab(at index: Int) {
        guard let tabs = mainTabBar.viewControllers, index < tabs.count else {
            KeyboardDiagnostics.logTimed("tab \(index + 1) absent")
            return
        }
        KeyboardDiagnostics.logTimed("tab \(index + 1)")
        mainTabBar.selectedIndex = index
    }
}
