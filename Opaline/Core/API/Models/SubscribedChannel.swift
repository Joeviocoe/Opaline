import Foundation

/// A channel from the user's subscriptions list (FEchannels browse).
struct SubscribedChannel: Codable {
    let id: String
    let title: String
    let avatarURL: String?
}
