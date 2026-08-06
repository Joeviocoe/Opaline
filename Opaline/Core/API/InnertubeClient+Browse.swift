import Foundation

// MARK: - Browse

extension InnertubeClient {
    static func sortedByPublishedDate(_ page: FeedPage) -> FeedPage {
        let dated = page.videos.enumerated().map { entry in
            (
                index: entry.offset,
                video: entry.element,
                date: entry.element.publishedAt.flatMap {
                    VideoFormatters.approximateDate(fromRelative: $0)
                } ?? .distantPast
            )
        }
        // Swift's sort is not guaranteed stable — tiebreak on the original
        // index so equal (coarse) dates keep the server's relative order.
        let sorted = dated.sorted {
            $0.date != $1.date ? $0.date > $1.date : $0.index < $1.index
        }
        return FeedPage(
            videos: sorted.map { $0.video },
            continuation: page.continuation,
            channels: page.channels
        )
    }

    func sendVote(
        endpoint: String,
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self.postVote(
                    endpoint: endpoint,
                    videoId: videoId,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    func authenticatedBrowse(
        browseId: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeBrowse(
                    browseId: browseId,
                    continuation: nil,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    /// The TVHTML5 subscriptions feed switched to a relevance-first layout
    /// (a "Most relevant" shelf plus per-channel shelves), losing the
    /// chronological order. The WEB client rejects the device-flow token
    /// (HTTP 400 precondition), so the order is restored client-side from
    /// the videos' relative published dates, newest first.
    func subscriptionsBrowse(
        browseId: String?,
        continuation: String?,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        executeBrowse(
            browseId: browseId,
            continuation: continuation,
            token: token
        ) { result in
            completion(result.map(Self.sortedByPublishedDate))
        }
    }

    func executeWebBrowse(
        browseId: String?,
        continuation: String?,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = webContext
        if let cont = continuation {
            body["continuation"] = cont
        } else if let bid = browseId {
            body["browseId"] = bid
        }
        let headers = webBrowseHeaders(token: token)
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: headers,
            logTag: "webBrowse"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parseWebBrowsePage(json)
            let label = browseId ?? "continuation"
            if page.videos.isEmpty {
                let keys = json.keys.joined(separator: ", ")
                AppLog.innertube(
                    "web browse '\(label)': 0 videos. topKeys=[\(keys)]"
                )
            } else {
                AppLog.innertube(
                    "web browse '\(label)': \(page.videos.count) videos"
                )
            }
            return page
        } completion: { completion($0) }
    }

    func executeTVHistoryBrowse(
        token: String,
        continuation: String?,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        if let cont = continuation {
            body["continuation"] = cont
        } else {
            body[JSONKey.browseId] = BrowseID.history
        }
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "tvHistory"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parseTVHistoryPage(json)
            let hasCont = page.continuation != nil
            AppLog.innertube(
                "TV history: \(page.videos.count) videos, cont=\(hasCont)"
            )
            return page
        } completion: { completion($0) }
    }

    func fetchHistoryProgress(
        completion: @escaping (
            ([String: Double], [String: String])
        ) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            guard let self,
                  case let .success(token) = result
            else {
                completion(([:], [:]))
                return
            }
            self.executeHistoryFetch(
                token: token,
                completion: completion
            )
        }
    }

    func executeBrowseAnonymous(
        browseId: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        body["browseId"] = browseId
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: anonHeaders(),
            logTag: "browseAnon(\(browseId))"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parsePageJSON(json)
            if page.videos.isEmpty {
                AppLog.innertube(
                    "executeBrowseAnonymous: empty for browseId=\(browseId)"
                )
                return nil
            }
            return page
        } completion: { completion($0) }
    }

    func executeBrowse(
        browseId: String?,
        continuation: String?,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        if let cont = continuation {
            body["continuation"] = cont
        } else if let bid = browseId {
            body["browseId"] = bid
        }
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "browse(\(browseId ?? "cont"))"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parsePageJSON(json)
            return page.videos.isEmpty ? nil : page
        } completion: { completion($0) }
    }
}

// MARK: - Private Browse Helpers

private extension InnertubeClient {
    func executeHistoryFetch(
        token: String,
        completion: @escaping (
            ([String: Double], [String: String])
        ) -> Void
    ) {
        var body = tvContext
        body[JSONKey.browseId] = BrowseID.history
        let url = baseURL + InnertubeEndpoint.browse
        execute(
            urlString: url,
            body: body,
            headers: authHeaders(token: token),
            logTag: "progressSync"
        ) { json -> (progress: [String: Double], thumbnails: [String: String])? in
            let progress = InnertubeClient
                .extractProgressFromHistory(json)
            let thumbs = InnertubeClient
                .extractThumbnailsFromHistory(json)
            return (progress, thumbs)
        } completion: { result in
            let data = try? result.get()
            let pCount = data?.progress.count ?? 0
            let tCount = data?.thumbnails.count ?? 0
            AppLog.log(
                "ProgressSync",
                "\(pCount) progress, \(tCount) thumbs"
            )
            completion(data ?? ([:], [:]))
        }
    }

    func postVote(
        endpoint: String,
        videoId: String,
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["target"] = ["videoId": videoId]
        let headers: [String: String] = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.authorization: "Bearer \(token)",
            HTTPHeader.xYoutubeClientName: "7",
            HTTPHeader.xYoutubeClientVersion: "7.20260311.12.00"
        ]
        AppLog.innertube(
            "sendVote '\(endpoint)' videoId=\(videoId)"
        )
        execute(
            urlString: "\(baseURL)/\(endpoint)",
            body: body,
            headers: headers,
            logTag: "vote(\(endpoint))"
        ) { _ -> Void? in
            AppLog.innertube("sendVote '\(endpoint)' success")
            return ()
        } completion: { completion($0) }
    }

    func webBrowseHeaders(token: String) -> [String: String] {
        [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.authorization: "Bearer \(token)",
            HTTPHeader.xYoutubeClientName: "1",
            HTTPHeader.xYoutubeClientVersion: "2.20260206.01.00",
            HTTPHeader.userAgent: UserAgent.chromeDesktop,
            HTTPHeader.origin: AppURLs.YouTube.base,
            HTTPHeader.referer: AppURLs.YouTube.base + "/"
        ]
    }
}
