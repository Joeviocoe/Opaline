import Foundation

// MARK: - Watch Page Parsing
extension InnertubeClient {
    static func parseWatchMetadata(
        _ json: [String: Any]
    ) -> WatchMetadata {
        if let renderer = firstRenderer(
            in: json,
            named: "slimVideoMetadataRenderer"
        ) {
            return parseSlimMeta(renderer)
        }
        if let renderer = firstRenderer(
            in: json,
            named: "videoMetadataRenderer"
        ) {
            return WatchMetadata(
                title: simpleText(
                    from: renderer["title"]
                ),
                viewCountText: simpleText(
                    from: renderer["viewCountText"]
                ),
                publishedText: simpleText(
                    from: renderer["dateText"]
                )
            )
        }
        return WatchMetadata(
            title: nil,
            viewCountText: nil,
            publishedText: nil
        )
    }

    static func parseWatchDescription(
        _ json: [String: Any]
    ) -> String? {
        let descKey =
            "expandableVideoDescriptionBodyRenderer"
        if let renderer = firstRenderer(
            in: json, named: descKey
        ) {
            return simpleText(
                from: renderer["descriptionBodyText"]
            ) ?? simpleText(
                from: renderer["showMoreText"]
            )
        }
        if let renderer = firstRenderer(
            in: json,
            named: "videoMetadataRenderer"
        ) {
            return simpleText(
                from: renderer["description"]
            )
        }
        return nil
    }

    static func parseWatchChannelInfo(
        _ json: [String: Any],
        fallbackVideo: Video
    ) -> ChannelInfo? {
        if let info = parseAvatarLockup(
            json, fallbackVideo: fallbackVideo
        ) {
            return completed(info, from: json)
        }
        return derivedChannelInfo(json, fallbackVideo: fallbackVideo)
    }

    /// A lockup can parse without a thumbnail or a name; the owner renderer
    /// carries both, so it fills whatever the lockup left empty.
    private static func completed(
        _ info: ChannelInfo, from json: [String: Any]
    ) -> ChannelInfo {
        let owner = extractOwnerInfo(json)
        guard info.avatarURL == nil || info.title.isEmpty else {
            return info
        }
        return ChannelInfo(
            id: info.id,
            title: info.title.isEmpty
                ? (owner.title ?? info.title) : info.title,
            avatarURL: info.avatarURL ?? owner.avatarURL,
            subscriberCountText: info.subscriberCountText,
            bannerURL: info.bannerURL,
            isVerified: info.isVerified,
            description: info.description,
            contactInfo: info.contactInfo,
            videoCountText: info.videoCountText
        )
    }

    private static func derivedChannelInfo(
        _ json: [String: Any],
        fallbackVideo: Video
    ) -> ChannelInfo? {
        var enriched = enrichWithOwnerInfo(
            json, video: fallbackVideo
        )
        if enriched.channelName.isEmpty,
           let name = extractOwnerInfo(json).title {
            enriched.channelName = name
        }
        if let info = buildFallbackChannel(
            fallbackVideo: enriched
        ) {
            return info
        }
        return fallbackBrowseIdChannel(
            json, video: fallbackVideo
        )
    }

    private static func enrichWithOwnerInfo(
        _ json: [String: Any],
        video: Video
    ) -> Video {
        // Gate on what is actually missing, not on the channelId alone: a
        // short opened from a feed already knows its channel but has no
        // avatar, and the owner renderer is the only place the watch page
        // carries one.
        guard video.channelId == nil || video.channelAvatarURL == nil else {
            return video
        }
        let owner = extractOwnerInfo(json)
        guard owner.channelId != nil || owner.avatarURL != nil else {
            return video
        }
        // A copy, not a rebuild: a rebuild silently drops whatever the model
        // gains next, and it already carries the renderer's feedback actions.
        var enriched = video
        enriched.channelId = video.channelId ?? owner.channelId
        enriched.channelAvatarURL = video.channelAvatarURL ?? owner.avatarURL
        return enriched
    }

    private static func fallbackBrowseIdChannel(
        _ json: [String: Any],
        video: Video
    ) -> ChannelInfo? {
        guard let chId = firstMatchingBrowseId(
            in: json
        ) else {
            return nil
        }
        return ChannelInfo(
            id: chId,
            title: video.channelName,
            avatarURL: nil,
            subscriberCountText: nil,
            bannerURL: nil,
            isVerified: false,
            description: nil,
            contactInfo: nil,
            videoCountText: nil
        )
    }
}

// MARK: - Private Watch Helpers
private extension InnertubeClient {
    static func parseSlimMeta(
        _ renderer: [String: Any]
    ) -> WatchMetadata {
        let title = simpleText(
            from: renderer["title"]
        )
        let lines = renderer["lines"]
            as? [[String: Any]] ?? []
        var parts: [String] = []
        for line in lines {
            appendLineParts(
                line: line, parts: &parts
            )
        }
        return WatchMetadata(
            title: title,
            viewCountText: parts.first,
            publishedText: parts.dropFirst().first
        )
    }

    static func appendLineParts(
        line: [String: Any],
        parts: inout [String]
    ) {
        let lineItems = (line["lineRenderer"]
            as? [String: Any])?["items"]
            as? [[String: Any]] ?? []
        for item in lineItems {
            let rdr = item["lineItemRenderer"]
                as? [String: Any]
            let text = simpleText(
                from: rdr?["text"]
            )
            if let text = text, !text.isEmpty,
               text != "•" {
                parts.append(text)
            }
        }
    }

    static func parseAvatarLockup(
        _ json: [String: Any],
        fallbackVideo: Video
    ) -> ChannelInfo? {
        guard let lockup = firstRenderer(
            in: json,
            named: "avatarLockupRenderer"
        ) else {
            return nil
        }
        let avatarURL = extractThumbnailURL(from: lockup["avatar"])
            ?? extractThumbnailURL(from: lockup["thumbnail"])
        let title = simpleText(from: lockup["title"]) ?? fallbackVideo.channelName
        let subtitle = simpleText(from: lockup["subtitle"])
        let chId = firstMatchingBrowseId(in: lockup) ?? fallbackVideo.channelId ?? ""
        guard !title.isEmpty || avatarURL != nil
        else {
            return nil
        }
        return ChannelInfo(
            id: chId,
            title: title,
            avatarURL: avatarURL,
            subscriberCountText: subtitle,
            bannerURL: nil,
            isVerified: false,
            description: nil,
            contactInfo: nil,
            videoCountText: nil
        )
    }

    static func buildFallbackChannel(
        fallbackVideo: Video
    ) -> ChannelInfo? {
        guard let chId = fallbackVideo.channelId
        else {
            return nil
        }
        return ChannelInfo(
            id: chId,
            title: fallbackVideo.channelName,
            avatarURL: fallbackVideo.channelAvatarURL,
            subscriberCountText: nil,
            bannerURL: nil,
            isVerified: false,
            description: nil,
            contactInfo: nil,
            videoCountText: nil
        )
    }
}
