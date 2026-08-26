import Foundation

/// One server-offered feedback action for a video: "Remove from watch
/// history", "Not interested", "Don't recommend channel", "Hide". The label
/// comes from YouTube already worded for the surface it was sent on, so
/// nothing here is localized — and which actions a video carries depends on
/// where it was fetched from, which is why they ride on the `Video` that
/// came out of that response rather than living in a table keyed by video
/// id (#105, #106).
struct FeedbackAction: Codable {
    let label: String
    /// `iconType` as sent, when the renderer carried one — the only
    /// language-independent hint at what the action is.
    let icon: String?
    let token: String
}
