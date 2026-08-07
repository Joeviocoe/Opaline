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
            // The lockup can parse without a thumbnail; returning it as-is
            // meant the owner renderer — which does carry one — was never
            // consulted, and the channel showed up with no avatar.
            guard info.avatarURL == nil,
                  let avatar = extractOwnerInfo(json).avatarURL else {
                return info
            }
            return ChannelInfo(
                id: info.id,
                title: info.title,
                avatarURL: avatar,
                subscriberCountText: info.subscriberCountText,
                bannerURL: info.bannerURL,
                isVerified: info.isVerified,
                description: info.description,
                contactInfo: info.contactInfo,
                videoCountText: info.videoCountText
            )
        }
        let enriched = enrichWithOwnerInfo(
            json, video: fallbackVideo
        )
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
        return Video(
            id: video.id,
            title: video.title,
            channelId: video.channelId ?? owner.channelId,
            channelName: video.channelName,
            channelAvatarURL: video.channelAvatarURL ?? owner.avatarURL,
            thumbnailURL: video.thumbnailURL,
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            duration: video.duration,
            isLive: video.isLive,
            playlistId: video.playlistId,
            isShort: video.isShort
        )
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

    // Extract channelId + avatarURL from slimOwnerRenderer / videoOwnerRenderer
    private static func extractOwnerInfo(
        _ json: [String: Any]
    ) -> (channelId: String?, avatarURL: String?) {
        for name in [
            "slimOwnerRenderer",
            "videoOwnerRenderer",
            "ownerRenderer",
            "channelThumbnailWithLinkRenderer"
        ] {
            guard let owner = firstRenderer(
                in: json, named: name
            ) else { continue }
            let chId = firstMatchingBrowseId(in: owner)
                .flatMap { $0.isEmpty ? nil : $0 }
            let avatarURL = extractThumbnailURL(
                from: owner["thumbnail"]
            )
            if chId != nil || avatarURL != nil {
                return (chId, avatarURL)
            }
        }
        return (nil, nil)
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
            if let text, !text.isEmpty,
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
