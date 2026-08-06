import Foundation

/// One page of the endless Shorts swipe feed.
struct ShortsSequencePage {
    /// Videos to append, in swipe order. Only `id`/`thumbnailURL` are known
    /// here — the sequence endpoint returns no titles; the viewer fills the
    /// rest from the watch page once a short becomes current.
    let videos: [Video]
    /// Token for the next page, fed back as `seed`.
    let continuation: String?
}

extension InnertubeClient: ShortsService {
    /// Fetches the next batch of the Shorts sequence.
    ///
    /// - Parameter seed: either a continuation token from a previous page or
    ///   a videoId (encoded by `ShortsSeed.params`) to start a fresh feed.
    func fetchShortsSequence(
        seed: String,
        completion: @escaping (Result<ShortsSequencePage, Error>) -> Void
    ) {
        // Signed in, the sequence is personalised — it comes back drawn from
        // the subscribed channels, which is what the official app swipes
        // through. Anonymously the same call returns generic recommendations.
        // TVHTML5 is the client our device-flow token is valid for; the WEB
        // client rejects it (the same reason the subscriptions feed uses TV).
        guard OAuthClient.shared.isSignedIn else {
            executeShortsSequence(seed: seed, token: nil, completion: completion)
            return
        }
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .success(let token):
                self?.executeShortsSequence(
                    seed: seed, token: token, completion: completion
                )
            case .failure:
                self?.executeShortsSequence(
                    seed: seed, token: nil, completion: completion
                )
            }
        }
    }

    private func executeShortsSequence(
        seed: String,
        token: String?,
        completion: @escaping (Result<ShortsSequencePage, Error>) -> Void
    ) {
        var body = token == nil ? webContext : tvContext
        body["sequenceParams"] = seed
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.reelSequence)",
            body: body,
            headers: token.map { authHeaders(token: $0) } ?? anonHeaders(),
            logTag: "shortsSequence"
        ) { json -> ShortsSequencePage? in
            Self.parseShortsSequence(json)
        } completion: { completion($0) }
    }
}

/// Builds the `sequenceParams` protobuf that seeds a feed.
///
/// Field 1 = the video the sequence continues from (excluded from the
/// entries). Field 5 = the candidate pool, a repeated message of
/// `{1: {1: videoId}}`. The pool is what keeps a feed on topic: sending the
/// subscriptions shelf's shorts is how the official app stays inside
/// subscribed channels while still letting the server pick the order. With
/// no pool the server answers with generic recommendations — decoded from a
/// live `reelWatchEndpoint`.
enum ShortsSeed {
    static func params(videoId: String, pool: [String] = []) -> String {
        var bytes = lengthDelimited(field: 1, payload: Array(videoId.utf8))
        if !pool.isEmpty {
            var entries: [UInt8] = []
            for id in pool {
                let inner = lengthDelimited(field: 1, payload: Array(id.utf8))
                entries += lengthDelimited(field: 1, payload: inner)
            }
            bytes += lengthDelimited(field: 5, payload: entries)
        }
        return Data(bytes).base64EncodedString()
    }

    /// One length-delimited protobuf field. Lengths above 127 need a varint,
    /// which a pool of more than a handful of ids always exceeds.
    private static func lengthDelimited(
        field: UInt8, payload: [UInt8]
    ) -> [UInt8] {
        var out: [UInt8] = [field << 3 | 2]
        var length = payload.count
        while length > 0x7F {
            out.append(UInt8(length & 0x7F) | 0x80)
            length >>= 7
        }
        out.append(UInt8(length))
        return out + payload
    }
}

// MARK: - Parsing

extension InnertubeClient {
    static func parseShortsSequence(
        _ json: [String: Any]
    ) -> ShortsSequencePage? {
        guard let entries = json["entries"] as? [[String: Any]] else {
            return nil
        }
        let videos: [Video] = entries.compactMap { entry in
            guard let endpoint = entry.digDict(
                "command", "reelWatchEndpoint"
            ) else {
                return nil
            }
            return shortsVideo(fromReelWatchEndpoint: endpoint)
        }
        // WEB nests the token; the TV client returns a bare `continuation`
        // string. Missing the TV shape capped the feed at one page.
        let token = json["continuation"] as? String
            ?? json.digDict(
                "continuationEndpoint", "continuationCommand"
            )?["token"] as? String
        return ShortsSequencePage(videos: videos, continuation: token)
    }

    /// A `reelWatchEndpoint` carries the videoId and a poster frame but no
    /// title or channel — those arrive with the watch page.
    static func shortsVideo(
        fromReelWatchEndpoint endpoint: [String: Any]
    ) -> Video? {
        guard let videoId = endpoint[JSONKey.videoId] as? String else {
            return nil
        }
        let thumbnails = endpoint.digArray("thumbnail", JSONKey.thumbnails)
        let thumbnail = thumbnails?.last?[JSONKey.url] as? String
        return Video(
            id: videoId,
            title: "",
            channelId: nil,
            channelName: "",
            channelAvatarURL: nil,
            thumbnailURL: thumbnail ?? "",
            viewCount: nil,
            publishedAt: nil,
            duration: nil,
            isShort: true
        )
    }
}

extension InnertubeClient {
    /// Parses a `shortsLockupViewModel` grid item.
    static func parseShortsLockup(_ lockup: [String: Any]) -> Video? {
        guard let endpoint = lockup.digDict(
            "onTap", "innertubeCommand", "reelWatchEndpoint"
        ), let base = shortsVideo(fromReelWatchEndpoint: endpoint) else {
            return nil
        }
        let meta = lockup.digDict("overlayMetadata")
        let sources = lockup.digArray(
            "thumbnailViewModel", "image", "sources"
        )
        let thumbnail = sources?.first?[JSONKey.url] as? String
        return Video(
            id: base.id,
            title: meta.flatMap {
                ($0["primaryText"] as? [String: Any])?["content"] as? String
            } ?? "",
            channelId: nil,
            channelName: "",
            channelAvatarURL: nil,
            thumbnailURL: thumbnail ?? base.thumbnailURL,
            viewCount: meta.flatMap {
                ($0["secondaryText"] as? [String: Any])?["content"] as? String
            },
            publishedAt: nil,
            duration: nil,
            isShort: true
        )
    }
}
