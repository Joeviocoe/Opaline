import Foundation

/// A titled run of videos inside a page. `count` consecutive videos
/// of `FeedPage.videos` belong to this shelf, in order.
struct FeedShelf: Codable {
    let title: String?
    let count: Int
    /// The shelf's own "more of this row" token (rails page with it).
    var continuation: String?
}

/// A shelf's "more of this row" token, kept with the shelf title so
/// drained pages can stay labeled in the UI.
struct ShelfContinuation: Codable {
    let title: String?
    let token: String
}

struct FeedPage: Codable {
    var videos: [Video]
    var continuation: String?
    /// Subscribed channels found in the page (TV subscriptions
    /// responses include a channel row). Nil for other feeds.
    var channels: [SubscribedChannel]?
    /// Shelf partition of `videos` (for section headers). Nil means
    /// one untitled section.
    var shelves: [FeedShelf]?
    /// Per-shelf continuation tokens. The TV home section list ends
    /// after ~6 pages (~100 videos); these keep the feed scrolling
    /// once it is exhausted.
    var shelfContinuations: [ShelfContinuation]?
}

// MARK: - ISP-compliant service protocols
//
// Each protocol covers exactly one responsibility.
// ViewControllers depend only on the protocol they use, not the full VideoService.

protocol FeedService: AnyObject {
    func fetchHomeFeed(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    /// One-shot TV category page (`BrowseID.*Destination`) — same shape
    /// as the home feed but without continuations.
    func fetchCategoryFeed(
        browseId: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchSubscriptionFeed(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    /// Subscriptions pagination — its continuation tokens come from a
    /// different client surface than the home feed's.
    func fetchSubscriptionsNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
}

protocol HistoryService: AnyObject {
    func fetchHistory(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchHistoryNextPage(
        continuation: String,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
}

protocol SearchService: AnyObject {
    // Pass `continuation` from the previous page to fetch the next one
    // (filters are baked into it — they only apply to the first page).
    // swiftlint:disable:next function_parameter_count
    func search(
        query: String,
        filters: SearchFilters?,
        continuation: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<SearchPage, Error>) -> Void
    )
    /// Autocomplete suggestions for a partial query.
    func fetchSearchSuggestions(
        query: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<[String], Error>) -> Void
    )
}

protocol PlaylistService: AnyObject {
    func fetchPlaylists(
        completion: @escaping (Result<[Playlist], Error>) -> Void
    )
    /// Save targets for one video, flagged with whether it is already there.
    func fetchAddToPlaylistOptions(
        videoId: String,
        completion: @escaping (Result<[PlaylistAddOption], Error>) -> Void
    )
    /// Playlist contents arrive in 15-video pages; pass the previous
    /// page's `continuation` to fetch the next one.
    func fetchPlaylistVideos(
        playlistId: String,
        continuation: String?,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
}

protocol ChannelService: AnyObject {
    func fetchChannelInfo(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    )
    func fetchChannelPage(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    )
    func enrichChannelInfo(
        channelId: String,
        tvInfo: ChannelInfo,
        onEnriched: @escaping (ChannelInfo) -> Void
    )
}

struct ChannelBrowseAction {
    let channelId: String
    let params: String
}

struct ChannelFilterChip {
    enum Action {
        case continuation(token: String)
        case browse(ChannelBrowseAction)
    }
    let label: String
    let action: Action
    var params: String {
        switch action {
        case .continuation(let token):
            return token
        case .browse(let browseAction):
            return browseAction.params
        }
    }
}

struct ChannelTabPage {
    let feedPage: FeedPage
    let filterChips: [ChannelFilterChip]
}

struct PlaylistsPage {
    let playlists: [Playlist]
    let continuation: String?
    var filterChips: [ChannelFilterChip] = []
}

protocol ChannelTabService: AnyObject {
    func fetchChannelTab(
        channelId: String,
        params: String,
        completion: @escaping (Result<ChannelTabPage, Error>) -> Void
    )
    func fetchChannelTabNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchChannelPlaylists(
        channelId: String,
        params: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    )
    func fetchChannelPlaylistsNextPage(
        continuation: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    )
}

/// The endless Shorts swipe feed.
protocol ShortsService: AnyObject {
    func fetchShortsSequence(
        seed: String,
        completion: @escaping (Result<ShortsSequencePage, Error>) -> Void
    )
}

protocol WatchService: AnyObject {
    func fetchWatchPage(
        video: Video,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    )
    // swiftlint:disable:next function_parameter_count
    func fetchDirectPlayback(
        videoId: String,
        client: PlaybackClient,
        poToken: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    )
    func fetchComments(
        videoId: String,
        continuation: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    )
    /// The queue past the window the watch page carried, and the queue
    /// re-ordered by the server. Only the queue panel asks for either.
    func fetchQueuePage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchShuffledQueue(
        video: Video,
        params: String,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    )
    func fetchWatchtimeURLs(
        videoId: String,
        completion: @escaping (WatchtimeURLs?) -> Void
    )
    /// Caption tracks via the IOS player client (works where the WEB
    /// client's timedtext URLs are POT-gated and return empty bodies).
    func fetchCaptionTracks(
        videoId: String,
        completion: @escaping ([SubtitleTrack]) -> Void
    )
    /// Audio-track (dub) metadata via the IOS player client — the cheapest
    /// reliable listing (no STS, pot, or watch-page scrape needed).
    func fetchAudioTrackList(
        videoId: String,
        completion: @escaping ([AudioTrackInfo]) -> Void
    )
}

protocol EngagementService: AnyObject {
    func sendLike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func sendDislike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func removeLike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func subscribeToChannel(
        channelId: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func unsubscribeFromChannel(
        channelId: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func editPlaylist(
        playlistId: String,
        actions: [[String: Any]],
        completion: @escaping (Result<Void, Error>) -> Void
    )
    /// Sends one of the feedback tokens a renderer offered — removing a
    /// video from watch history, or telling the feed it missed.
    func sendFeedback(
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

protocol SubscribedChannelsService: AnyObject {
    func fetchSubscribedChannels(
        completion: @escaping (Result<[SubscribedChannel], Error>) -> Void
    )
}

protocol AccountService: AnyObject {
    func fetchAccountInfo(
        completion: @escaping (
            Result<(name: String, avatarURL: String?), Error>
        ) -> Void
    )
}

// MARK: - Composite umbrella
typealias VideoService =
    FeedService & HistoryService & SearchService
    & PlaylistService & ChannelService & WatchService
    & EngagementService & AccountService
    & SubscribedChannelsService
