import Foundation

// MARK: - Pivot Parsing (Mix / Playlist)

extension InnertubeClient {
    static func parsePivotPlaylist(
        json: [String: Any],
        currentVideoId: String
    )
        -> (title: String, videos: [Video])? {
        // Only ever called for a watch that carried a playlistId — see
        // `parseWatchPage`. The pivot itself is no evidence: since 2026-07 it
        // carries generic 3-item suggestion shelves for EVERY video, and the
        // one being watched turns up in plenty of them.
        for section in pivotSections(from: json) {
            let videos = extractPivotVideos(from: section)
            guard videos.contains(where: { $0.id == currentVideoId }) else {
                continue
            }
            return (extractPivotTitle(from: section), videos)
        }
        return nil
    }

    /// The related list, in the order the server sent it: shelves top to
    /// bottom, items left to right. Read by sweeping the whole response for
    /// tile renderers instead, it came out in `Dictionary.values` order —
    /// which Swift randomises per process, so the same video could hand back
    /// a differently ordered list on the next launch.
    /// `excludingIds` carries the queue as well as the video being watched:
    /// a playlist's own shelf sits in the same pivot, so without it the whole
    /// queue turns up a second time down in the related list.
    static func relatedFromPivot(
        json: [String: Any],
        excludingIds: Set<String>
    ) -> [Video] {
        var seen = excludingIds
        return pivotSections(from: json)
            .flatMap { extractPivotVideos(from: $0) }
            .filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Private Helpers

private extension InnertubeClient {
    static func pivotSections(
        from json: [String: Any]
    )
        -> [[String: Any]] {
        json.digArray(
            "contents",
            "singleColumnWatchNextResults",
            "pivot",
            "sectionListRenderer",
            "contents"
        ) ?? []
    }

    static func extractPivotVideos(
        from section: [String: Any]
    )
        -> [Video] {
        let shelf = section["shelfRenderer"]
            as? [String: Any]
        let content = shelf?["content"]
            as? [String: Any]
        let horizontal = content?[
            "horizontalListRenderer"
        ] as? [String: Any]
        let items = horizontal?["items"]
            as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let tile = item["tileRenderer"]
                as? [String: Any]
            else {
                return nil
            }
            return parseTileRenderer(tile)
        }
    }

    static func extractPivotTitle(
        from section: [String: Any]
    )
        -> String {
        let shelf = section["shelfRenderer"]
            as? [String: Any]
        // Current responses put the header under `headerRenderer`;
        // older ones used `header`.
        let header = shelf?["headerRenderer"] as? [String: Any]
            ?? shelf?["header"] as? [String: Any]
        let titleRenderer = header?[
            "playlistShelfHeaderRenderer"
        ] as? [String: Any]
        return simpleText(from: titleRenderer?["title"])
            ?? "player.related.mix".localized
    }
}
