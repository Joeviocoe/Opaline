import Foundation

// MARK: - Subscribed Channels

extension InnertubeClient {
    /// Extracts unique subscribed channels from any Innertube JSON
    /// subtree. Handles both web `channelRenderer` items and TV
    /// channel tiles (`tileRenderer` with a channel browseEndpoint).
    static func subscribedChannels(
        in node: Any
    ) -> [SubscribedChannel] {
        var channels: [SubscribedChannel] = []
        var seenIds: Set<String> = []
        collectChannelNodes(in: node) { channel in
            if seenIds.insert(channel.id).inserted {
                channels.append(channel)
            }
        }
        return channels
    }

    /// Fetches the full subscriptions channel list via the TV
    /// client (FEchannels). The OAuth token is TV-scoped, so all
    /// authenticated calls must use the TV context.
    func fetchSubscribedChannels(
        completion: @escaping (Result<[SubscribedChannel], Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeSubscribedChannelsBrowse(
                    token: token,
                    completion: completion
                )
            }
        }
    }
}

// MARK: - Private Helpers

private extension InnertubeClient {
    static func collectChannelNodes(
        in node: Any,
        onFound: (SubscribedChannel) -> Void
    ) {
        if let dict = node as? [String: Any] {
            if let renderer = dict[RendererKey.channel] as? [String: Any],
               let channel = channelFromRenderer(renderer) {
                onFound(channel)
            }
            if let tile = dict[RendererKey.tile] as? [String: Any],
               let channel = channelFromTile(tile) {
                onFound(channel)
            }
            for value in dict.values {
                collectChannelNodes(in: value, onFound: onFound)
            }
        } else if let array = node as? [Any] {
            for item in array {
                collectChannelNodes(in: item, onFound: onFound)
            }
        }
    }

    static func channelFromRenderer(
        _ renderer: [String: Any]
    ) -> SubscribedChannel? {
        guard let id = renderer["channelId"] as? String,
              let title = renderer.innertubeText(JSONKey.title)
        else {
            return nil
        }
        let avatar = renderer.thumbnailURL().map {
            normalizeThumbnailURL($0)
        }
        return SubscribedChannel(id: id, title: title, avatarURL: avatar)
    }

    static func channelFromTile(
        _ tile: [String: Any]
    ) -> SubscribedChannel? {
        guard let browseId = tile.digString(
            "onSelectCommand",
            "browseEndpoint",
            JSONKey.browseId
        ), browseId.hasPrefix("UC") else {
            return nil
        }
        let meta = tile.digDict("metadata", RendererKey.tileMetadata)
        guard let title = simpleText(from: meta?[JSONKey.title]),
              !title.isEmpty
        else {
            return nil
        }
        let header = tile.digDict(JSONKey.header, RendererKey.tileHeader)
        let avatar = header?.thumbnailURL().map {
            normalizeThumbnailURL($0)
        }
        return SubscribedChannel(
            id: browseId,
            title: title,
            avatarURL: avatar
        )
    }

    func executeSubscribedChannelsBrowse(
        token: String,
        completion: @escaping (Result<[SubscribedChannel], Error>) -> Void
    ) {
        var body = tvContext
        body[JSONKey.browseId] = BrowseID.channels
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "subscribedChannels"
        ) { json -> [SubscribedChannel]? in
            let channels = InnertubeClient.subscribedChannels(in: json)
            AppLog.innertube(
                "subscribedChannels: \(channels.count) channels"
            )
            return channels.isEmpty ? nil : channels
        } completion: { completion($0) }
    }
}
