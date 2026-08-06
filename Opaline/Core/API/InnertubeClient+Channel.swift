import Foundation

// MARK: - Channel

extension InnertubeClient {
    func executeChannelBrowse(
        channelId: String,
        token: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        executeChannelBrowse(
            channelId: channelId,
            token: token,
            context: tvContext,
            completion: completion
        )
    }

    func executeChannelBrowse(
        channelId: String,
        token: String,
        context: [String: Any],
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        var body = context
        body["browseId"] = channelId
        let clientName = Self.extractClientName(from: context)
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "channelBrowse(\(clientName),\(channelId))"
        ) { json -> ChannelInfo? in
            InnertubeClient.parseChannelInfo(
                json,
                fallbackChannelId: channelId
            )
        } completion: { completion($0) }
    }

    func executeChannelPageBrowse(
        channelId: String,
        token: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        guard let url = URL(string: browseURL) else {
            completion(.failure(APIError.invalidURL))
            return
        }
        var tvBody = tvContext
        tvBody["browseId"] = channelId
        guard let tvData = try? JSONSerialization.data(withJSONObject: tvBody) else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        api.post(url: url, body: tvData, headers: authHeaders(token: token)) { result in
            guard let page = Self.handleChannelPageTVOnly(
                result,
                channelId: channelId
            ) else {
                completion(.failure(APIError.decodingFailed))
                return
            }
            completion(.success(page))
        }
    }

    func fetchWebChannelEnrichment(
        channelId: String,
        token: String,
        tvInfo: ChannelInfo,
        onEnriched: @escaping (ChannelInfo) -> Void
    ) {
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        guard let url = URL(string: browseURL) else {
            return
        }
        var webBody = webContext
        webBody["browseId"] = channelId
        guard let webData = try? JSONSerialization.data(withJSONObject: webBody) else {
            return
        }
        api.post(url: url, body: webData, headers: anonHeaders()) { result in
            guard case .success(let wData) = result,
                  let wJson = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                  let webInfo = Self.parseChannelInfo(wJson, fallbackChannelId: channelId)
            else { return }
            let merged = Self.mergeWebChannelInfo(
                tvInfo: tvInfo,
                webInfo: webInfo
            )
            DispatchQueue.main.async {
                onEnriched(merged)
            }
        }
    }
}

// MARK: - Private Channel Helpers

private extension InnertubeClient {
    static func extractClientName(
        from context: [String: Any]
    ) -> String {
        let ctx = context["context"] as? [String: Any]
        let client = ctx?["client"] as? [String: Any]
        return client?["clientName"] as? String ?? "unknown"
    }

    static func handleChannelPageTVOnly(
        _ result: Result<Data, Error>,
        channelId: String
    ) -> ChannelPage? {
        guard let tvInfo = parseTVChannelData(
            result,
            channelId: channelId
        ),
            let tvJson = parseTVJson(from: result)
        else {
            return nil
        }
        let page = parsePageJSON(tvJson)
        let subState = parseSubscribeState(tvJson)
        logChannelResult(tvInfo)
        return ChannelPage(
            info: tvInfo,
            videosPage: page,
            subscribeButtonText: subState.text,
            isSubscribed: subState.isSubscribed
        )
    }

    static func parseTVChannelData(
        _ result: Result<Data, Error>,
        channelId: String
    ) -> ChannelInfo? {
        guard let tvJson = parseTVJson(from: result) else {
            return nil
        }
        return parseChannelInfo(
            tvJson,
            fallbackChannelId: channelId
        )
    }

    static func parseTVJson(
        from result: Result<Data, Error>
    ) -> [String: Any]? {
        guard case .success(let tvData) = result else {
            return nil
        }
        return try? JSONSerialization.jsonObject(
            with: tvData
        ) as? [String: Any]
    }

    static func mergeWebChannelInfo(
        tvInfo: ChannelInfo,
        webInfo: ChannelInfo
    ) -> ChannelInfo {
        ChannelInfo(
            id: tvInfo.id,
            title: tvInfo.title.isEmpty ? webInfo.title : tvInfo.title,
            avatarURL: tvInfo.avatarURL ?? webInfo.avatarURL,
            subscriberCountText: webInfo.subscriberCountText
                ?? tvInfo.subscriberCountText,
            bannerURL: webInfo.bannerURL ?? tvInfo.bannerURL,
            isVerified: webInfo.isVerified || tvInfo.isVerified,
            description: webInfo.description ?? tvInfo.description,
            contactInfo: webInfo.contactInfo ?? tvInfo.contactInfo,
            videoCountText: webInfo.videoCountText ?? tvInfo.videoCountText
        )
    }

    static func logChannelResult(_ info: ChannelInfo) {
        let subs = info.subscriberCountText ?? "nil"
        let hasBanner = info.bannerURL != nil
        AppLog.channel(
            "parsed: title='\(info.title)' subs='\(subs)' "
                + "banner=\(hasBanner) verified=\(info.isVerified)"
        )
    }
}
