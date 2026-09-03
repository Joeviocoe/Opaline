import Foundation

enum ServiceContainer {
    /// The app-wide HTTP transport: the URLSession core wrapped in decorators
    /// (logging now; authorizing/retrying to follow). Every service should route
    /// through this rather than touching URLSession directly.
    static let transport: HTTPTransport = LoggingTransport(
        AuthorizingTransport(URLSessionTransport())
    )

    /// Undecorated transport for the high-volume media plane (images, avatars):
    /// no per-request logging spam and no auth (these requests are anonymous).
    ///
    /// Its own session, capped: a page of twenty thumbnails fired at once
    /// shares one narrow link and they all land together seconds later, so
    /// the whole grid stays grey and then fills in a single blink. A few at
    /// a time finish one after another and the grid fills as you read it —
    /// each image costs 20-40ms on its own. The cap also keeps thumbnails
    /// out of the API session's connection pool.
    ///
    /// ponytail: fixed cap; make it link-aware only if it misbehaves on wifi.
    static let mediaTransport: HTTPTransport = URLSessionTransport(
        session: URLSession(configuration: mediaSessionConfiguration)
    )

    private static var mediaSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3
        return config
    }

    // Single InnertubeClient instance shared across all service protocols.
    // Each property is typed to the narrowest protocol the caller needs — DIP in action.
    private static let client = InnertubeClient(transport: transport)

    /// Wrapped so the subscriptions feed is assembled on the device from
    /// each channel's Atom feed when there is no account; signed in it is
    /// the plain client, and every other feed passes straight through.
    static var feed: FeedService { localFeed }
    /// Wrapped for the new-content dots, which ask for watch history
    /// generically. The History *screen* branches to the store itself.
    static var history: HistoryService { localHistory }
    static var search: SearchService { client }
    static var playlists: PlaylistService { client }
    /// Wrapped so a channel page loads with no account, over the anonymous
    /// WEB browse instead of the token-gated TV one.
    static var channel: ChannelService { localChannel }
    static var channelTabs: ChannelTabService { client }
    /// Wrapped so the avatar bar and channel filter read the local
    /// subscription store with no account.
    static var subscribedChannels: SubscribedChannelsService {
        localSubscribedChannels
    }
    /// Wrapped so a downloaded video keeps its page when the network is
    /// gone; online it is the plain client.
    static var watch: WatchService { offlineWatch }

    private static let offlineWatch = OfflineWatchService(wrapping: client)
    private static let localFeed = LocalSubscriptionFeedService(
        wrapping: client
    )
    private static let localHistory = LocalHistoryService(wrapping: client)
    private static let localSubscribedChannels =
        LocalSubscribedChannelsService(wrapping: client)
    private static let localEngagement = LocalEngagementService(
        wrapping: client
    )
    private static let localChannel = LocalChannelService(
        wrapping: client, anonymous: client
    )
    /// Wrapped so subscribing with no account writes to the local store.
    /// Likes and feedback pass through and still fail signed out, which is
    /// correct — there is nothing local about a like.
    static var engagement: EngagementService { localEngagement }
    static var account: AccountService { client }
    static var shorts: ShortsService { client }

    /// Legacy accessor — prefer narrow protocols above for new code.
    static var video: VideoService { client }

    /// Public per-channel Atom feeds for the new-content dots —
    /// anonymous traffic, so it rides the undecorated media transport.
    static let channelRSS: ChannelRSSFeedService = ChannelRSSService(
        transport: mediaTransport
    )

    /// Content-language/region preferences for Innertube requests
    /// (localization plan Phase 2 points `InnertubeContexts` here).
    static let localePreferences: LocalePreferences = DefaultLocalePreferences()
}
