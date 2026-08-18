import UIKit

struct AppDependencies {
    let feedService: FeedService
    let historyService: HistoryService
    let playlistService: PlaylistService
    let searchService: SearchService
    let channelService: ChannelService
    let channelTabService: ChannelTabService
    let watchService: WatchService
    let engagementService: EngagementService
    let accountService: AccountService
    let subscribedChannelsService: SubscribedChannelsService
    let shortsService: ShortsService
    let channelRSSService: ChannelRSSFeedService
    let localePreferences: LocalePreferences

    static func live() -> AppDependencies {
        AppDependencies(
            feedService: ServiceContainer.feed,
            historyService: ServiceContainer.history,
            playlistService: ServiceContainer.playlists,
            searchService: ServiceContainer.search,
            channelService: ServiceContainer.channel,
            channelTabService: ServiceContainer.channelTabs,
            watchService: ServiceContainer.watch,
            engagementService: ServiceContainer.engagement,
            accountService: ServiceContainer.account,
            subscribedChannelsService: ServiceContainer.subscribedChannels,
            shortsService: ServiceContainer.shorts,
            channelRSSService: ServiceContainer.channelRSS,
            localePreferences: ServiceContainer.localePreferences
        )
    }

    func makePlaylistViewController(playlist: Playlist) -> UIViewController {
        PlaylistVideosViewController(
            playlist: playlist,
            service: playlistService,
            channelViewControllerFactory: makeChannelViewController
        )
    }

    func makeSearchViewController() -> SearchViewController {
        SearchViewController(
            service: searchService,
            channelViewControllerFactory: makeChannelViewController
        )
    }

    func makeWatchViewController(video: Video) -> WatchViewController {
        WatchViewController(
            video: video,
            watchService: watchService,
            engagementService: engagementService,
            playlistService: playlistService,
            channelInfoStore: .shared
        )
    }

    func makeShortsViewController(
        seedVideo: Video?, entry: ShortsEntry
    ) -> ShortsViewController {
        ShortsViewController(
            seedVideo: seedVideo,
            entry: entry,
            shortsService: shortsService,
            watchService: watchService,
            engagementService: engagementService,
            channelViewControllerFactory: makeChannelViewController
        )
    }

    func makeSubscriptionsViewController() -> SubscriptionsViewController {
        SubscriptionsViewController(dependencies: self)
    }

    func makeChannelViewController(
        channelId: String,
        channelName: String
    ) -> ChannelViewController {
        ChannelViewController(
            channelId: channelId,
            channelName: channelName,
            channelService: channelService,
            feedService: feedService,
            engagementService: engagementService,
            channelTabService: channelTabService,
            playlistService: playlistService,
            channelViewControllerFactory: makeChannelViewController
        )
    }
}
