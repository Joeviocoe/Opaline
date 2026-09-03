import Foundation

/// The one place the "local when signed out, account when signed in" rule
/// lives for subscribing.
///
/// Every subscribe surface routes through here rather than calling
/// `EngagementService` directly, so identity is captured at the tap — signed
/// out there is no `fetchChannelInfo` to enrich a bare id afterwards, since
/// it is one of the calls that hard-fails without a token.
enum SubscribeAction {
    /// Subscribing is always offered now: with no account it goes to the
    /// local store instead of the server. This replaces the scattered
    /// `!isAnonymous` checks that used to hide the button entirely.
    static var isAvailable: Bool {
        true
    }

    /// The server's answer ORed with the local store, so a channel
    /// subscribed to on this device reads as subscribed even though the
    /// (anonymous) watch page says otherwise.
    static func isSubscribed(
        channelId: String?,
        serverSays: Bool
    ) -> Bool {
        guard LocalLibrary.isActive, let channelId = channelId else {
            return serverSays
        }
        return serverSays
            || LocalSubscriptionStore.shared.isSubscribed(
                channelId: channelId
            )
    }

    static func isSubscribed(video: Video) -> Bool {
        isSubscribed(channelId: video.channelId, serverSays: false)
    }

    /// Notes the identity, then performs the toggle. The engagement service
    /// is the decorated one, so signed out this lands in the local store and
    /// signed in it goes to YouTube — this function does not branch on it.
    ///
    /// Takes a `SubscribedChannel` rather than three loose fields because
    /// that is exactly what identity is here, and it keeps the signature
    /// inside SwiftLint's parameter count.
    static func toggle(
        channel: SubscribedChannel,
        wasSubscribed: Bool,
        engagement: EngagementService = ServiceContainer.engagement,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        LocalChannelIdentity.shared.remember(channel)
        AppLog.subscribe(
            "\(wasSubscribed ? "unsubscribe" : "subscribe") \(channel.id)"
                + " local=\(LocalLibrary.isActive)"
        )
        if wasSubscribed {
            engagement.unsubscribeFromChannel(
                channelId: channel.id,
                completion: completion
            )
        } else {
            engagement.subscribeToChannel(
                channelId: channel.id,
                completion: completion
            )
        }
    }

    /// Convenience for the surfaces that hold a `Video` — the action menu
    /// and anywhere else a card is the only context. Everything needed is
    /// already on the card, so identity capture costs nothing there.
    static func toggle(
        video: Video,
        wasSubscribed: Bool,
        engagement: EngagementService = ServiceContainer.engagement,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let channelId = video.channelId, !channelId.isEmpty else {
            completion(.failure(APIError.invalidResponse))
            return
        }
        toggle(
            channel: SubscribedChannel(
                id: channelId,
                title: video.channelName,
                avatarURL: video.channelAvatarURL
            ),
            wasSubscribed: wasSubscribed,
            engagement: engagement,
            completion: completion
        )
    }
}
