import Foundation

// MARK: - Playback & Subscriptions
extension InnertubeClient {
    func executeWatchNext(
        video: Video,
        token: String,
        anonymous: Bool = false,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        var body = anonymous ? webContext : tvContext
        body["videoId"] = video.id
        if let pid = video.playlistId {
            body["playlistId"] = pid
            body["params"] = "OALAAQE%3D"
        }
        var headers = anonHeaders()
        if !anonymous && !token.isEmpty {
            headers[HTTPHeader.authorization] = "Bearer \(token)"
        }
        let nextURL = "\(baseURL)\(InnertubeEndpoint.next)"
        execute(
            urlString: nextURL,
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            logTag: "watchNext(\(video.id))"
        ) { json -> WatchPage? in
            InnertubeClient.parseWatchPage(
                json,
                fallbackVideo: video
            )
        } completion: { completion($0) }
    }

    // MARK: Comments

    func executeComments(
        videoId: String,
        continuation: String?,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    ) {
        var body = webContext
        body["continuation"] = continuation
            ?? Self.buildCommentsContinuation(
                videoId: videoId,
                sortBy: 0,
                commentId: nil
            )
        let headers: [String: String] = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.xYoutubeClientName:
                DirectPlaybackClient.web.clientHeaderName,
            HTTPHeader.xYoutubeClientVersion:
                DirectPlaybackClient.web.clientVersion
        ]
        let nextURL = "\(baseURL)\(InnertubeEndpoint.next)"
        execute(
            urlString: nextURL,
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            logTag: "comments(\(videoId))"
        ) { json -> CommentsPage? in
            Self.parseCommentsPage(json)
        } completion: { completion($0) }
    }

    func executeDirectPlayback(
        videoId: String,
        client: DirectPlaybackClient,
        token: String,
        poToken: String? = nil,
        visitorData: String? = nil,
        signatureTimestamp: Int? = nil,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        let body = buildDirectPlaybackBody(
            videoId: videoId,
            client: client,
            poToken: poToken,
            signatureTimestamp: signatureTimestamp
        )
        let headers = client.apiHeaders(token: token, visitorData: visitorData)
        let playerURL = "\(baseURL)/player\(client.playerURLSuffix)"
        var hitBotCheck = false
        execute(
            urlString: playerURL,
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            sendsCookies: client.sendsCookies,
            logTag: "directPlayback(\(client))"
        ) { json -> DirectPlaybackInfo? in
            Self.parseDirectPlayback(
                json: json, videoId: videoId, client: client
            ) { hitBotCheck = true }
        } completion: { result in
            // A bot check is worth telling the user about — "playback failed"
            // sends them hunting for a problem in the app.
            if case .failure = result, hitBotCheck {
                completion(.failure(APIError.botCheck))
            } else {
                completion(result)
            }
        }
    }

    /// Anonymous MWEB playback: POSTs /player with the mobile-web context +
    /// STS + `pot` + `visitorData`. The signatureTimestamp is mandatory (else
    /// UNPLAYABLE "page needs reloaded") and MUST match the player used to
    /// solve `n` — the caller scrapes both from the same watch page; a stale
    /// STS gets every media range 403'd. Falls back to the site-wide STS
    /// only when the caller has none.
    func fetchMWebPlayback(
        videoId: String,
        poToken: String?,
        visitorData: String?,
        signatureTimestamp: Int? = nil,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        let run: (Int?) -> Void = { [weak self] sts in
            guard let self, cancellationToken?.isCancelled != true else {
                return
            }
            self.executeDirectPlayback(
                videoId: videoId,
                client: .mweb,
                token: "",
                poToken: poToken,
                visitorData: visitorData,
                signatureTimestamp: sts,
                cancellationToken: cancellationToken,
                completion: completion
            )
        }
        if let signatureTimestamp {
            run(signatureTimestamp)
        } else {
            SignatureTimestampService.shared.fetch { run($0) }
        }
    }

    func executeSubscribe(
        channelId: String,
        token: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["channelIds"] = [channelId]
        AppLog.innertube("executeSubscribe channelId=\(channelId)")
        let subURL = "\(baseURL)\(InnertubeEndpoint.subscribe)"
        execute(
            urlString: subURL,
            body: body,
            headers: authHeaders(token: token),
            cancellationToken: cancellationToken,
            logTag: "subscribe(\(channelId))"
        ) { _ -> Void? in
            ()
        } completion: { completion($0) }
    }

    func executeUnsubscribe(
        channelId: String,
        token: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["channelIds"] = [channelId]
        AppLog.innertube(
            "executeUnsubscribe channelId=\(channelId)"
        )
        let unsubURL = "\(baseURL)\(InnertubeEndpoint.unsubscribe)"
        execute(
            urlString: unsubURL,
            body: body,
            headers: authHeaders(token: token),
            cancellationToken: cancellationToken,
            logTag: "unsubscribe(\(channelId))"
        ) { _ -> Void? in
            ()
        } completion: { completion($0) }
    }

    func executeWatchtimeURLs(
        videoId: String,
        token: String,
        signatureTimestamp: Int?,
        completion: @escaping (WatchtimeURLs?) -> Void
    ) {
        var body = tvContext
        body["videoId"] = videoId
        body["racyCheckOk"] = true
        body["contentCheckOk"] = true
        // TV wants its own timestamp format: the web value with a "001" suffix
        // (web 20522 → tv 20522001). Sending the web one back is what makes it
        // answer UNPLAYABLE "The page needs to be reloaded".
        if let sts = signatureTimestamp.flatMap({ Int("\($0)001") }) {
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "signatureTimestamp": sts
                ]
            ]
        }
        let playerURL =
            "\(baseURL)\(InnertubeEndpoint.player)"
        execute(
            urlString: playerURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "watchtimeURLs(\(videoId))"
        ) { json -> WatchtimeURLs? in
            InnertubeClient.extractWatchtimeURLs(json)
        } completion: { result in
            completion(try? result.get())
        }
    }
}

private extension InnertubeClient {
    func buildDirectPlaybackBody(
        videoId: String,
        client: DirectPlaybackClient,
        poToken: String?,
        signatureTimestamp: Int? = nil
    ) -> [String: Any] {
        var body = client.context
        body["videoId"] = videoId
        if client.requiresContentCheckFlags {
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
            var playbackCtx: [String: Any] = [
                "html5Preference": "HTML5_PREF_WANTS"
            ]
            if let signatureTimestamp {
                playbackCtx["signatureTimestamp"] = signatureTimestamp
            }
            body["playbackContext"] = [
                "contentPlaybackContext": playbackCtx
            ]
        }
        if let poToken, !poToken.isEmpty {
            body["serviceIntegrityDimensions"] = [
                "poToken": poToken
            ]
        }
        return body
    }
}
