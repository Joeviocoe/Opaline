import Foundation

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
    /// Search restricted to one channel. Carries no `SearchFilters` —
    /// this surface has none, see `fetchChannelSearch`.
    func fetchChannelSearch(
        channelId: String,
        query: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchChannelSearchNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
}
