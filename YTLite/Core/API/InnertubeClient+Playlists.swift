import Foundation

// MARK: - Playlists

extension InnertubeClient {
    func executePlaylistsFetch(
        token: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        var body = tvContext
        body[JSONKey.browseId] = BrowseID.library
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistsFetch"
        ) { json -> [Playlist]? in
            Self.parsePlaylistTabs(json)
        } completion: { [weak self] result in
            guard let self else {
                return
            }
            self.handlePlaylistsFetchResult(
                result,
                token: token,
                completion: completion
            )
        }
    }

    func executePlaylistVideosFetch(
        playlistId: String,
        continuation: String?,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        if let continuation {
            body[JSONKey.continuation] = continuation
        } else {
            body[JSONKey.browseId] = "VL\(playlistId)"
        }
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistVideos(\(playlistId))"
        ) { json -> FeedPage? in
            let list = Self.playlistVideoList(from: json)
            let videos = Self.playlistVideos(from: list)
            let next = Self.playlistContinuation(from: list)
            AppLog.innertube(
                "playlist \(playlistId): \(videos.count) videos"
                    + " cont=\(next != nil)"
            )
            return videos.isEmpty
                ? nil
                : FeedPage(videos: videos, continuation: next)
        } completion: { completion($0) }
    }
}

// MARK: - Private Playlist Helpers

private extension InnertubeClient {
    static func parsePlaylistTabs(
        _ json: [String: Any]
    ) -> [Playlist]? {
        let contents = json["contents"] as? [String: Any]
        let browse = contents?["tvBrowseRenderer"] as? [String: Any]
        let tabs = browse?["content"] as? [String: Any]
        let navRenderer = tabs?["tvSecondaryNavRenderer"] as? [String: Any]
        let sections = navRenderer?["sections"] as? [[String: Any]] ?? []
        let secRenderer = sections.first?["tvSecondaryNavSectionRenderer"]
        let secDict = secRenderer as? [String: Any]
        let allTabs = secDict?["tabs"] as? [[String: Any]] ?? []
        return allTabs.compactMap { tab in
            parsePlaylistTab(tab)
        }
    }

    static func parsePlaylistTab(
        _ tab: [String: Any]
    ) -> Playlist? {
        guard let tr = tab["tabRenderer"] as? [String: Any],
              let title = tr["title"] as? String,
              let endpoint = tr["endpoint"] as? [String: Any],
              let browse = endpoint["browseEndpoint"] as? [String: Any],
              let params = browse["params"] as? String,
              let playlistId = extractPlaylistIdFromParams(params)
        else {
            return nil
        }
        return Playlist(
            id: playlistId,
            title: title,
            description: "",
            thumbnailURL: nil,
            itemCount: nil
        )
    }

    /// The list renderer for both shapes: page one nests it under the
    /// browse surface, continuation pages return it at the top level.
    static func playlistVideoList(
        from json: [String: Any]
    ) -> [String: Any]? {
        if let continued = (
            json["continuationContents"] as? [String: Any]
        )?["playlistVideoListContinuation"] as? [String: Any] {
            return continued
        }
        let contents = json["contents"] as? [String: Any]
        let browse = contents?["tvBrowseRenderer"] as? [String: Any]
        let rightCol = browse?["content"] as? [String: Any]
        let surface = rightCol?["tvSurfaceContentRenderer"] as? [String: Any]
        let surfaceContent = surface?["content"] as? [String: Any]
        let twoCol = surfaceContent?["twoColumnRenderer"] as? [String: Any]
        let right = twoCol?["rightColumn"] as? [String: Any]
        return right?["playlistVideoListRenderer"] as? [String: Any]
    }

    static func playlistVideos(
        from list: [String: Any]?
    ) -> [Video] {
        let items = list?["contents"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let tile = item["tileRenderer"] as? [String: Any],
                  let header = tile["header"] as? [String: Any],
                  let thr = header["tileHeaderRenderer"] as? [String: Any],
                  thr["thumbnailOverlays"] != nil
            else {
                return nil
            }
            return InnertubeClient.parseTileRenderer(tile)
        }
    }

    static func playlistContinuation(
        from list: [String: Any]?
    ) -> String? {
        let continuations = list?["continuations"] as? [[String: Any]]
        let next = continuations?.first?["nextContinuationData"]
            as? [String: Any]
        return next?["continuation"] as? String
    }

    static func playlistVideoItems(
        from json: [String: Any]
    ) -> [[String: Any]] {
        playlistVideoList(from: json)?["contents"] as? [[String: Any]] ?? []
    }

    /// Playlists the TV library browse never lists: Watch Later, and the
    /// legacy Favorites list on accounts old enough to have one.
    static func implicitPlaylists(
        besides playlists: [Playlist]
    ) -> [Playlist] {
        let known = Set(playlists.map(\.id))
        let watchLater = Playlist(
            id: "WL",
            title: "Watch Later",
            description: "",
            thumbnailURL: nil,
            itemCount: nil
        )
        let legacy = legacyFavoritesId.map {
            Playlist(
                id: $0,
                title: "library.playlists.favorites".localized,
                description: "",
                thumbnailURL: nil,
                itemCount: nil
            )
        }
        return ([watchLater] + [legacy].compactMap { $0 })
            .filter { !known.contains($0.id) }
    }

    func handlePlaylistsFetchResult(
        _ result: Result<[Playlist], Error>,
        token: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            completion(.failure(error))
        case .success(let playlists):
            let all = Self.implicitPlaylists(besides: playlists)
                + playlists
            guard !all.isEmpty else {
                completion(.success(all))
                return
            }
            fetchAllThumbnails(
                playlists: all,
                token: token,
                completion: completion
            )
        }
    }

    func fetchAllThumbnails(
        playlists: [Playlist],
        token: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        let group = DispatchGroup()
        var thumbnails: [String: String] = [:]
        let lock = NSLock()
        for playlist in playlists {
            group.enter()
            fetchPlaylistFirstThumbnail(
                playlistId: playlist.id,
                token: token
            ) { url in
                if let url {
                    lock.lock()
                    thumbnails[playlist.id] = url
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .global()) {
            let result = playlists.map { pl in
                Playlist(
                    id: pl.id,
                    title: pl.title,
                    description: pl.description,
                    thumbnailURL: thumbnails[pl.id],
                    itemCount: pl.itemCount
                )
            }
            completion(.success(result))
        }
    }

    func fetchPlaylistFirstThumbnail(
        playlistId: String,
        token: String,
        completion: @escaping (String?) -> Void
    ) {
        var body = tvContext
        body["browseId"] = "VL\(playlistId)"
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistThumb(\(playlistId))"
        ) { json -> String? in
            let items = Self.playlistVideoItems(from: json)
            for item in items {
                if let tile = item["tileRenderer"] as? [String: Any],
                   let video = InnertubeClient.parseTileRenderer(tile) {
                    return video.thumbnailURL
                }
            }
            return nil
        } completion: { result in
            completion(try? result.get())
        }
    }
}
