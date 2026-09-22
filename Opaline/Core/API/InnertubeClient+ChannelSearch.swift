import Foundation

extension InnertubeClient {
    /// Channel-scoped search — the channel's own Search tab, served by the
    /// same browse endpoint its other tabs use. The search filters have no
    /// place here: YouTube itself offers none on this surface and the
    /// endpoint ignores any that are encoded into `params` (Opaline#117).
    func fetchChannelSearch(
        channelId: String,
        query: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.browseId] = channelId
        body[JSONKey.params] = ChannelTabParams.search
        body["query"] = query
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelSearch(\(channelId))"
        ) { json -> FeedPage? in
            Self.parseChannelSearchPage(json)
        } completion: { completion($0) }
    }

    func fetchChannelSearchNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.continuation] = continuation
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelSearchNext"
        ) { json -> FeedPage? in
            Self.parseChannelSearchPage(json)
        } completion: { completion($0) }
    }
}
