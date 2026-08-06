import Foundation

// MARK: - Tile Helpers
extension InnertubeClient {
    static func buildTileVideo(
        videoId: String,
        title: String,
        tile: [String: Any],
        meta: [String: Any]?,
        playlistId: String? = nil
    ) -> Video {
        let lines = meta?["lines"] as? [[String: Any]] ?? []
        let channel = extractTileChannel(from: lines)
        let chId = extractChannelId(from: tile, firstLineItems: channel.items)
        let chAvatar = extractChannelAvatarURL(from: tile)
        let thumbInfo = resolveTileThumb(videoId: videoId, tile: tile)
        let overlay = parseTileOverlay(tile: tile)
        let timing = parseTileTiming(lines: lines)
        logThumbnailChoice(
            videoId: videoId,
            chosenURL: thumbInfo.url,
            fallbackURL: thumbInfo.raw
        )
        return Video(
            id: videoId,
            title: title,
            channelId: chId,
            channelName: channel.name,
            channelAvatarURL: chAvatar,
            thumbnailURL: thumbInfo.url,
            viewCount: timing.viewCount,
            publishedAt: timing.publishedAt,
            duration: overlay.duration,
            isLive: overlay.isLive,
            playlistId: playlistId
        )
    }

    /// TILE_STYLE_YTLR_CAROUSEL (the Live destination's spotlight
    /// rail) keeps its metadata in onFocusCommand →
    /// updateCarouselHeaderCommand instead of tileMetadataRenderer.
    static func parseCarouselTile(
        _ tile: [String: Any],
        videoId: String
    ) -> Video? {
        guard let spotlight = carouselSpotlight(in: tile),
              let title = simpleText(from: spotlight[JSONKey.title])
        else {
            return nil
        }
        let byline = carouselByline(in: spotlight)
        let thumb = resolveTileThumb(videoId: videoId, tile: tile)
        let isLive = tile.digString(
            "onSelectCommand", "watchEndpoint", "ustreamerConfig"
        ) != nil
        return Video(
            id: videoId,
            title: title,
            channelId: nil,
            channelName: byline.name,
            channelAvatarURL: byline.avatarURL,
            thumbnailURL: thumb.url,
            viewCount: nil,
            publishedAt: nil,
            duration: nil,
            isLive: isLive
        )
    }

    static func checkOverlayLive(
        _ overlaysAny: Any?
    ) -> Bool {
        let overlays = overlaysAny
            as? [[String: Any]] ?? []
        let key = RendererKey
            .thumbnailOverlayTimeStatus
        return overlays.contains {
            ($0[key] as? [String: Any])?["style"]
                as? String == "LIVE"
        }
    }
}

// MARK: - Private Tile Helpers
private extension InnertubeClient {
    static func carouselSpotlight(
        in tile: [String: Any]
    ) -> [String: Any]? {
        let commands = tile.digDict(
            "onFocusCommand", "commandExecutorCommand"
        )?["commands"] as? [[String: Any]] ?? []
        for command in commands {
            if let spotlight = command.digDict(
                "updateCarouselHeaderCommand",
                "spotlight",
                "entityMetadataRenderer"
            ) {
                return spotlight
            }
        }
        return nil
    }

    static func carouselByline(
        in spotlight: [String: Any]
    ) -> (name: String, avatarURL: String?) {
        let bylines = spotlight["bylines"] as? [[String: Any]] ?? []
        let items = (bylines.first?[RendererKey.line] as? [String: Any])?[
            JSONKey.items
        ] as? [[String: Any]] ?? []
        var name = ""
        var avatarURL: String?
        for item in items {
            guard let lineItem = item[RendererKey.lineItem]
                as? [String: Any]
            else {
                continue
            }
            if let text = simpleText(from: lineItem[JSONKey.text]) {
                name = text
            }
            if avatarURL == nil {
                avatarURL = lineItem.thumbnailURL()
            }
        }
        return (name, avatarURL)
    }

    static func extractTileChannel(
        from lines: [[String: Any]]
    ) -> (name: String, items: [[String: Any]]) {
        let lineKey = RendererKey.line
        let firstLine = lines.first?[lineKey]
            as? [String: Any]
        let items = firstLine?[JSONKey.items]
            as? [[String: Any]] ?? []
        let name = items.first.flatMap { li in
            let rdr = li[RendererKey.lineItem]
                as? [String: Any]
            return simpleText(
                from: rdr?[JSONKey.text]
            )
        } ?? ""
        return (name, items)
    }

    static func resolveTileThumb(
        videoId: String,
        tile: [String: Any]
    ) -> (url: String, raw: String) {
        let hdr = tile.digDict(
            JSONKey.header,
            RendererKey.tileHeader
        )
        let raw = hdr?.thumbnailURL() ?? ""
        let url = preferredThumbnailURL(
            videoId: videoId,
            fallbackURL: raw
        )
        return (url, raw)
    }

    static func parseTileOverlay(
        tile: [String: Any]
    ) -> (isLive: Bool, duration: String?) {
        let hdr = tile.digDict(
            JSONKey.header,
            RendererKey.tileHeader
        )
        let overlays = hdr?["thumbnailOverlays"]
            as? [[String: Any]] ?? []
        let isLive = checkOverlayLive(overlays)
        let duration: String? = isLive
            ? nil : overlayDuration(overlays)
        return (isLive, duration)
    }

    static func overlayDuration(
        _ overlays: [[String: Any]]
    ) -> String? {
        let key = RendererKey
            .thumbnailOverlayTimeStatus
        return overlays.compactMap { overlay in
            let rdr = overlay[key]
                as? [String: Any]
            return simpleText(
                from: rdr?[JSONKey.text]
            )
        }.first
    }

    static func parseTileTiming(
        lines: [[String: Any]]
    ) -> (viewCount: String?, publishedAt: String?) {
        guard lines.count > 1 else {
            return (nil, nil)
        }
        let lineDict = lines[1][RendererKey.line]
            as? [String: Any]
        let items = lineDict?[JSONKey.items]
            as? [[String: Any]] ?? []
        var viewCount: String?
        var publishedAt: String?
        for li in items {
            let rdr = li[RendererKey.lineItem]
                as? [String: Any]
            let text = simpleText(
                from: rdr?[JSONKey.text]
            ) ?? ""
            classifyTimingText(
                text,
                viewCount: &viewCount,
                publishedAt: &publishedAt
            )
        }
        return (viewCount, publishedAt)
    }

    static func classifyTimingText(
        _ text: String,
        viewCount: inout String?,
        publishedAt: inout String?
    ) {
        let skip = text == "•" || text == "·"
        guard !skip, !text.isEmpty else {
            return
        }
        if isViewCountText(text) {
            viewCount = text
        } else if isPublishedText(text) {
            publishedAt = text
        } else if viewCount == nil {
            // Unrecognized language (no ContentKeywords table): keep the
            // server text instead of dropping it — the metadata line order
            // is "views, date". Only chronological SORTING needs a table.
            viewCount = text
        } else if publishedAt == nil {
            publishedAt = text
        }
    }

    // Keyword tables live in ContentKeywords (Core/Localization) —
    // adding a content language means adding its table there.
    static func isViewCountText(
        _ text: String
    ) -> Bool {
        ContentKeywords.isViewCount(text)
    }

    static func isPublishedText(
        _ text: String
    ) -> Bool {
        ContentKeywords.isPublished(text)
    }
}
