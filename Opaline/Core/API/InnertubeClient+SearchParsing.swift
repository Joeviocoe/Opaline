import Foundation

extension InnertubeClient {
    /// Parses both the initial search response and continuation responses
    /// into videos plus the next-page token.
    ///
    /// Item shapes are handled by `VideoRendererParserChain`, the same one
    /// every other surface uses — search used to hand-roll a traversal that
    /// knew `videoRenderer` alone, which dropped shorts (and with them the
    /// "show Shorts" setting), mixes and inline watch progress.
    static func parseSearchPage(
        _ data: Data
    ) -> SearchPage {
        guard let json = try? JSONSerialization
            .jsonObject(with: data) as? [String: Any]
        else {
            return SearchPage(videos: [], continuation: nil)
        }
        let sections = initialSearchSections(json)
            ?? continuationSearchSections(json)
            ?? []
        var videos: [Video] = []
        var token: String?
        for section in sections {
            let items = (section["itemSectionRenderer"]
                as? [String: Any])?["contents"] as? [[String: Any]]
                ?? [section]
            let parsed = VideoRendererParserChain.parse(items: items)
            videos += parsed.videos
            token = token ?? parsed.continuation
        }
        return SearchPage(videos: videos, continuation: token)
    }
}

private extension InnertubeClient {
    static func initialSearchSections(
        _ json: [String: Any]
    ) -> [[String: Any]]? {
        json.digArray(
            "contents",
            "twoColumnSearchResultsRenderer",
            "primaryContents",
            "sectionListRenderer",
            "contents"
        )
    }

    static func continuationSearchSections(
        _ json: [String: Any]
    ) -> [[String: Any]]? {
        guard let commands = json["onResponseReceivedCommands"]
            as? [[String: Any]]
        else {
            return nil
        }
        return commands
            .compactMap {
                $0.digArray(
                    "appendContinuationItemsAction",
                    "continuationItems"
                )
            }
            .first
    }
}
