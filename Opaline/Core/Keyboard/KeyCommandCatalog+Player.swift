import UIKit

/// The watch screen's set, split from the main catalog only to stay inside the
/// 300-line file limit the linter enforces.
extension KeyCommandCatalog {
    /// Used while the player owns the chain and nothing inside it is focused.
    static let player: [UIKeyCommand] = playerTransport + playerArrows

    static let shorts: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.upArrow,
            action: #selector(ShortsViewController.keyboardPreviousShort)
        ),
        KeyCommandInput.command(
            KeyCommandInput.downArrow,
            action: #selector(ShortsViewController.keyboardNextShort)
        ),
        KeyCommandInput.command(
            KeyCommandInput.space,
            action: #selector(ShortsViewController.keyboardTogglePlayback),
            titleKey: "keyboard.playPause"
        )
    ]
}

private extension KeyCommandCatalog {
    static let playerTransport: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.space,
            action: #selector(WatchViewController.keyboardTogglePlayPause),
            titleKey: "keyboard.playPause"
        ),
        KeyCommandInput.command(
            "k",
            action: #selector(WatchViewController.keyboardTogglePlayPause)
        ),
        KeyCommandInput.command(
            "j",
            action: #selector(WatchViewController.keyboardSeekBackFixed)
        ),
        KeyCommandInput.command(
            "l",
            action: #selector(WatchViewController.keyboardSeekForwardFixed)
        ),
        KeyCommandInput.command(
            "f",
            action: #selector(WatchViewController.keyboardToggleFullscreen),
            titleKey: "keyboard.fullscreen"
        ),
        KeyCommandInput.command(
            "m",
            action: #selector(WatchViewController.keyboardToggleMute),
            titleKey: "keyboard.mute"
        ),
        KeyCommandInput.command(
            "n",
            action: #selector(WatchViewController.keyboardPlayNext),
            titleKey: "keyboard.next"
        ),
        KeyCommandInput.command(
            "p",
            action: #selector(WatchViewController.keyboardPlayPrevious),
            titleKey: "keyboard.previous"
        ),
        // Bracket keys as the second pair for previous/next: they sit together
        // on the keyboard and leave the media keys free to mean seek.
        KeyCommandInput.command(
            "[",
            action: #selector(WatchViewController.keyboardPlayPrevious)
        ),
        KeyCommandInput.command(
            "]",
            action: #selector(WatchViewController.keyboardPlayNext)
        ),
        KeyCommandInput.command(
            "q",
            action: #selector(WatchViewController.keyboardShowQueue),
            titleKey: "keyboard.queue"
        ),
        KeyCommandInput.command(
            ",",
            action: #selector(WatchViewController.keyboardSlowDown)
        ),
        KeyCommandInput.command(
            ".",
            action: #selector(WatchViewController.keyboardSpeedUp)
        ),
        KeyCommandInput.command(
            KeyCommandInput.escape,
            action: #selector(WatchViewController.keyboardEscape),
            titleKey: "keyboard.close"
        ),
        KeyCommandInput.command(
            KeyCommandInput.backspace,
            action: #selector(WatchViewController.keyboardEscape)
        )
    ] + scrubCommands

    static let playerArrows: [UIKeyCommand] = [
        KeyCommandInput.command(
            KeyCommandInput.leftArrow,
            action: #selector(WatchViewController.keyboardSeekBack),
            titleKey: "keyboard.seekBack"
        ),
        KeyCommandInput.command(
            KeyCommandInput.rightArrow,
            action: #selector(WatchViewController.keyboardSeekForward),
            titleKey: "keyboard.seekForward"
        ),
        KeyCommandInput.command(
            KeyCommandInput.upArrow,
            action: #selector(WatchViewController.keyboardVolumeUp)
        ),
        KeyCommandInput.command(
            KeyCommandInput.downArrow,
            action: #selector(WatchViewController.keyboardVolumeDown)
        )
    ]

    /// 0-9 jump to that tenth of the video. Ten separate selectors because the
    /// only way to tell two commands apart from one action — `propertyList` —
    /// is iOS 13, and `UIPress.key` (which would carry the character) is 13.4.
    static let scrubCommands: [UIKeyCommand] = [
        KeyCommandInput.command("0", action: #selector(WatchViewController.keyboardScrub0)),
        KeyCommandInput.command("1", action: #selector(WatchViewController.keyboardScrub1)),
        KeyCommandInput.command("2", action: #selector(WatchViewController.keyboardScrub2)),
        KeyCommandInput.command("3", action: #selector(WatchViewController.keyboardScrub3)),
        KeyCommandInput.command("4", action: #selector(WatchViewController.keyboardScrub4)),
        KeyCommandInput.command("5", action: #selector(WatchViewController.keyboardScrub5)),
        KeyCommandInput.command("6", action: #selector(WatchViewController.keyboardScrub6)),
        KeyCommandInput.command("7", action: #selector(WatchViewController.keyboardScrub7)),
        KeyCommandInput.command("8", action: #selector(WatchViewController.keyboardScrub8)),
        KeyCommandInput.command("9", action: #selector(WatchViewController.keyboardScrub9))
    ]
}
