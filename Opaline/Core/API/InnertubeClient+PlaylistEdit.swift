import Foundation

// MARK: - Playlist editing

/// Unlike commenting, saving to a playlist exists in the TV interface, so the
/// device-flow token carries the permission — same shape as `sendVote`.
extension InnertubeClient {
    /// Playlists this video can be saved to, each flagged with whether it is
    /// already there. One request, no per-playlist round trips.
    func fetchAddToPlaylistOptions(
        videoId: String,
        completion: @escaping (Result<[PlaylistAddOption], Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeAddToPlaylistOptions(
                    videoId: videoId,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    /// `actions` come straight from the option's service endpoint.
    func editPlaylist(
        playlistId: String,
        actions: [[String: Any]],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeEditPlaylist(
                    playlistId: playlistId,
                    actions: actions,
                    token: token,
                    completion: completion
                )
            }
        }
    }
}

private extension InnertubeClient {
    func executeAddToPlaylistOptions(
        videoId: String,
        token: String,
        completion: @escaping (Result<[PlaylistAddOption], Error>) -> Void
    ) {
        var body = tvContext
        body["videoIds"] = [videoId]
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.addToPlaylist)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "addToPlaylistOptions(\(videoId))"
        ) { json -> [PlaylistAddOption]? in
            let options = Self.parseAddToPlaylistOptions(json)
            AppLog.innertube(
                "playlist options: \(options.count), "
                    + "added=\(options.filter(\.isAdded).count)"
            )
            Self.rememberLegacyFavorites(in: options)
            return options.isEmpty ? nil : options
        } completion: { completion($0) }
    }

    func executeEditPlaylist(
        playlistId: String,
        actions: [[String: Any]],
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["playlistId"] = playlistId
        body["actions"] = actions
        AppLog.innertube(
            "editPlaylist \(playlistId) actions=\(actions.count)"
        )
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.editPlaylist)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "editPlaylist(\(playlistId))"
        ) { json -> Void? in
            let status = json["status"] as? String
            AppLog.innertube("editPlaylist status=\(status ?? "nil")")
            return status == "STATUS_SUCCEEDED" ? () : nil
        } completion: { completion($0) }
    }
}

// MARK: - Parsing

extension InnertubeClient {
    /// Id of the pre-2013 "Favorites" playlist (`FL` + channelId), if this
    /// account still has one. The TV library browse never lists it, so the
    /// add-to-playlist response is the only place it surfaces.
    static var legacyFavoritesId: String? {
        UserDefaults.standard.string(
            forKey: UserDefaultsKeys.Playlists.legacyFavoritesId
        )
    }

    /// The accounts list carries the user's channel id as
    /// `offlineCacheKeyToken.clientCacheKey` — the channel id minus its `UC`
    /// prefix — and the legacy playlist id is `FL` + that. Lets Favorites show
    /// up right after sign-in instead of after the first video.
    static func rememberOwnChannelId(from json: [String: Any]) {
        guard let key = firstClientCacheKey(in: json), !key.isEmpty else {
            return
        }
        AppLog.innertube("own channel UC\(key), legacy FL\(key)")
        UserDefaults.standard.set(
            "UC" + key,
            forKey: UserDefaultsKeys.Account.ownChannelId
        )
        guard legacyFavoritesId == nil else {
            return
        }
        UserDefaults.standard.set(
            "FL" + key,
            forKey: UserDefaultsKeys.Playlists.legacyFavoritesId
        )
    }

    private static func firstClientCacheKey(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let key = dict["clientCacheKey"] as? String {
                return key
            }
            for child in dict.values {
                if let key = firstClientCacheKey(in: child) {
                    return key
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let key = firstClientCacheKey(in: child) {
                    return key
                }
            }
        }
        return nil
    }

    static func rememberLegacyFavorites(
        in options: [PlaylistAddOption]
    ) {
        guard let legacy = options.first(
            where: { $0.id.hasPrefix("FL") }
        ) else {
            return
        }
        UserDefaults.standard.set(
            legacy.id,
            forKey: UserDefaultsKeys.Playlists.legacyFavoritesId
        )
    }

    static func parseAddToPlaylistOptions(
        _ json: [String: Any]
    ) -> [PlaylistAddOption] {
        let contents = json["contents"] as? [[String: Any]] ?? []
        let renderers = contents.compactMap {
            ($0["addToPlaylistRenderer"] as? [String: Any])?[
                "playlists"
            ] as? [[String: Any]]
        }
        return renderers.flatMap { $0 }.compactMap {
            playlistAddOption(from: $0)
        }
    }

    private static func playlistAddOption(
        from item: [String: Any]
    ) -> PlaylistAddOption? {
        guard let renderer = item["playlistAddToOptionRenderer"]
            as? [String: Any],
            let id = renderer["playlistId"] as? String
        else {
            return nil
        }
        return PlaylistAddOption(
            id: id,
            title: simpleText(from: renderer["title"]) ?? id,
            isAdded: (renderer["containsSelectedVideos"] as? String)
                == "ALL",
            addActions: editActions(
                renderer["addToPlaylistServiceEndpoint"]
            ),
            removeActions: editActions(
                renderer["removeFromPlaylistServiceEndpoint"]
            )
        )
    }

    private static func editActions(
        _ endpoint: Any?
    ) -> [[String: Any]] {
        let edit = (endpoint as? [String: Any])?[
            "playlistEditEndpoint"
        ] as? [String: Any]
        return edit?["actions"] as? [[String: Any]] ?? []
    }
}
