import Foundation

extension InnertubeClient {
    /// First page and continuation both land as a flat list of
    /// `itemSectionRenderer`s holding one video each, closed by a
    /// continuation item — unlike the grid the other channel tabs return.
    static func parseChannelSearchPage(
        _ json: [String: Any]
    ) -> FeedPage? {
        let items = channelSearchSections(from: json).flatMap { section in
            channelSearchItems(in: section)
        }
        let parsed = VideoRendererParserChain.parse(items: items)
        AppLog.innertube(
            "channelSearch: videos=\(parsed.videos.count) "
                + "cont=\(parsed.continuation != nil)"
        )
        return FeedPage(
            videos: parsed.videos,
            continuation: parsed.continuation
        )
    }

    private static func channelSearchItems(
        in section: [String: Any]
    ) -> [[String: Any]] {
        if let contents = section.digArray(
            RendererKey.itemSection, JSONKey.contents
        ) {
            return contents
        }
        return section[RendererKey.continuationItem] != nil ? [section] : []
    }

    private static func channelSearchSections(
        from json: [String: Any]
    ) -> [[String: Any]] {
        if let actions = json["onResponseReceivedActions"] as? [[String: Any]] {
            return actions.flatMap {
                $0.digArray(
                    "appendContinuationItemsAction", "continuationItems"
                ) ?? []
            }
        }
        let tabs = json.digArray(
            JSONKey.contents, RendererKey.twoColumnBrowse, JSONKey.tabs
        ) ?? []
        // The Search tab arrives as an expandableTabRenderer, not the
        // tabRenderer every other channel tab uses.
        let selected = tabs
            .compactMap {
                $0[RendererKey.expandableTab] as? [String: Any]
                    ?? $0[RendererKey.tab] as? [String: Any]
            }
            .first { ($0["selected"] as? Bool) == true }
        return selected?.digArray(
            JSONKey.content, RendererKey.sectionList, JSONKey.contents
        ) ?? []
    }
}
