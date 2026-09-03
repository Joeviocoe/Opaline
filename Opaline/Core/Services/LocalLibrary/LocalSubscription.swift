import Foundation

/// A channel the user subscribed to on this device, with no account.
///
/// Durable, not a wire type: nothing upstream is free to reshape it. The
/// identity is captured at the moment of the tap, because signed out there
/// is no `fetchChannelInfo` to enrich an id afterwards — see
/// `LocalChannelIdentity`.
struct LocalSubscription: Codable {
    let channelId: String
    let title: String
    let avatarURL: String?
    /// Orders the avatar bar by recency, the way a server-side list arrives.
    let subscribedAt: Date

    /// Every field but the id decodes tolerantly, so a file written by a
    /// build that knew fewer fields still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelId = try container.decode(String.self, forKey: .channelId)
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        avatarURL = try container.decodeIfPresent(
            String.self, forKey: .avatarURL
        )
        subscribedAt = try container.decodeIfPresent(
            Date.self, forKey: .subscribedAt
        ) ?? Date()
    }

    init(
        channelId: String,
        title: String,
        avatarURL: String?,
        subscribedAt: Date = Date()
    ) {
        self.channelId = channelId
        self.title = title
        self.avatarURL = avatarURL
        self.subscribedAt = subscribedAt
    }

    /// The whole coupling to the wire model: every screen that shows a
    /// subscribed channel already speaks `SubscribedChannel`.
    var channel: SubscribedChannel {
        SubscribedChannel(
            id: channelId,
            title: title,
            avatarURL: avatarURL
        )
    }
}
