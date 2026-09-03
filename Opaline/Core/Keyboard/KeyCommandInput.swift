import UIKit

/// The `input` strings every `UIKeyCommand` in the app is built from, and the
/// single factory that builds them.
///
/// Two reasons this is one place. The mundane one: the
/// `init(input:modifierFlags:action:discoverabilityTitle:)` convenience is
/// `API_DEPRECATED_WITH_REPLACEMENT(..., ios(9.0, 13.0))`, so under the 14.5
/// SDK this target builds against it warns on every command. The undeprecated
/// route is the three-argument initializer plus the `discoverabilityTitle`
/// property, which is itself `API_AVAILABLE(ios(9.0))` — fine here, but only
/// worth writing once.
///
/// The load-bearing one: whether iOS 9.3 actually delivers a key command with
/// *no* modifier flags could not be settled without the device. iOS 9 is the
/// release that added modifier-less commands, so it should — but if it turns
/// out not to, every plain letter needs a `⌃` alias and every arrow an `⌥`
/// one. Because inputs are declared nowhere else, that is a change to this
/// file and to nothing else in the branch.
enum KeyCommandInput {
    static let space = " "
    static let tab = "\t"
    static let enter = "\r"
    static let slash = "/"
    /// The ZAGG folio has no Esc key, so backspace is an alias for it.
    /// `UIKeyInputDelete` would be the named constant, but that is iOS 15.
    static let backspace = "\u{8}"

    static let upArrow = UIKeyCommand.inputUpArrow
    static let downArrow = UIKeyCommand.inputDownArrow
    static let leftArrow = UIKeyCommand.inputLeftArrow
    static let rightArrow = UIKeyCommand.inputRightArrow
    static let escape = UIKeyCommand.inputEscape
    static let pageUp = UIKeyCommand.inputPageUp
    static let pageDown = UIKeyCommand.inputPageDown

    /// Builds a command. `titleKey` is a localization key, not a string: a
    /// command with no key is deliberately absent from the ⌘-hold HUD, which
    /// renders the union of titles along the whole responder chain and would
    /// otherwise overflow a 1024x768 screen. Untitled commands still fire.
    static func command(
        _ input: String,
        action: Selector,
        modifiers: UIKeyModifierFlags = [],
        titleKey: String? = nil
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: modifiers,
            action: action
        )
        if let titleKey = titleKey {
            command.discoverabilityTitle = titleKey.localized
        }
        return command
    }

    /// A readable form of an `input` for the log — a raw " " or "\t" in a log
    /// line is indistinguishable from the field separator around it.
    static func describe(_ input: String?) -> String {
        guard let input = input else {
            return "nil"
        }
        let names: [String: String] = [
            space: "space", tab: "tab", enter: "enter",
            upArrow: "up", downArrow: "down",
            leftArrow: "left", rightArrow: "right",
            escape: "esc", pageUp: "pageUp", pageDown: "pageDown",
            backspace: "backspace"
        ]
        return names[input] ?? input
    }
}
