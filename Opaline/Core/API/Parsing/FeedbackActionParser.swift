import Foundation

/// Pulls the feedback actions a renderer offers out of its menu.
///
/// Nothing here knows what the actions mean. YouTube sends each one with its
/// own translated label and an opaque token, and the app shows exactly what
/// it was sent — so "Remove from watch history", "Not interested" and
/// "Don't recommend channel" all arrive without a single case for any of
/// them, and a new one appears in the menu on its own (#105, #106).
enum FeedbackActionParser {
    /// Walks the whole renderer rather than a fixed path: the menu sits
    /// under a different key on almost every surface, and the tokens are
    /// what matters, not where they hang.
    static func actions(
        in value: Any,
        label: String? = nil,
        icon: String? = nil
    ) -> [FeedbackAction] {
        if let array = value as? [Any] {
            return array.flatMap { actions(in: $0, label: label, icon: icon) }
        }
        guard let dict = value as? [String: Any] else {
            return []
        }
        // The label and the icon belong to the menu item; the token hangs
        // two levels below them, inside the endpoint, so both are carried
        // down the walk.
        let itemLabel = InnertubeClient.simpleText(from: dict["text"]) ?? label
        let itemIcon = dict.digString("icon", "iconType") ?? icon
        if let token = dict.digString("feedbackEndpoint", "feedbackToken"),
           let itemLabel = itemLabel {
            return [FeedbackAction(label: itemLabel, icon: itemIcon, token: token)]
        }
        return dict.values.flatMap { actions(in: $0, label: itemLabel, icon: itemIcon) }
    }
}
