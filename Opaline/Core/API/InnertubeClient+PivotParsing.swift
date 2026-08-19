import Foundation

/// The queue shelf of a watch page: the window of items the server sent,
/// plus the two handles it offers on the rest of the playlist — a token for
/// the items past the window, and the `params` its Shuffle button carries.
struct PivotPlaylist {
    let title: String
    let videos: [Video]
    let continuation: String?
    let shuffleParams: String?
}

// MARK: - Pivot Parsing (Mix / Playlist)

extension InnertubeClient {
    static func parsePivotPlaylist(
        json: [String: Any],
        currentVideoId: String
    )
        -> PivotPlaylist? {
        // Only ever called for a watch that carried a playlistId — see
        // `parseWatchPage`. The pivot itself is no evidence: since 2026-07 it
        // carries generic 3-item suggestion shelves for EVERY video, and the
        // one being watched turns up in plenty of them.
        for section in pivotSections(from: json) {
            let list = horizontalList(from: section)
            let videos = tileVideos(from: list)
            guard videos.contains(where: { $0.id == currentVideoId }) else {
                continue
            }
            let shelf = section["shelfRenderer"] as? [String: Any]
            return PivotPlaylist(
                title: extractPivotTitle(from: section),
                videos: videos,
                continuation: continuationToken(from: list),
                shuffleParams: shuffleParams(from: shelf)
            )
        }
        return nil
    }

    /// A "Show more" page of the queue shelf, requested with the token the
    /// shelf (or the previous page) handed back.
    static func parseQueueContinuation(
        _ json: [String: Any]
    )
        -> FeedPage? {
        guard let list = json.digDict(
            "continuationContents",
            "horizontalListContinuation"
        ) else {
            return nil
        }
        return FeedPage(
            videos: tileVideos(from: list),
            continuation: continuationToken(from: list)
        )
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
        tileVideos(from: horizontalList(from: section))
    }

    static func horizontalList(
        from section: [String: Any]
    )
        -> [String: Any]? {
        section.digDict(
            "shelfRenderer",
            "content",
            "horizontalListRenderer"
        )
    }

    static func tileVideos(
        from list: [String: Any]?
    )
        -> [Video] {
        let items = list?["items"]
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

    /// Forward only. A playlist calls it `nextContinuationData` ("Show
    /// more"); a mix, which is a radio and has no fixed end, calls the same
    /// thing `nextRadioContinuationData` — read only the first name and a
    /// mix looked like a queue of exactly 20. The `reloadContinuationData`
    /// alongside them re-fetches the window in place: asking for that one
    /// pages in a circle.
    static func continuationToken(
        from list: [String: Any]?
    )
        -> String? {
        let entries = list?["continuations"]
            as? [[String: Any]] ?? []
        for key in ["nextContinuationData", "nextRadioContinuationData"] {
            if let token = entries.compactMap({
                $0.digString(key, "continuation")
            }).first {
                return token
            }
        }
        return nil
    }

    /// The shelf header's Shuffle button. Its `watchEndpoint.params` replace
    /// the plain playlist params on a `/next` call and the same queue comes
    /// back re-ordered — the shuffling is the server's, all the way through
    /// the playlist rather than across the window we happen to hold.
    static func shuffleParams(
        from shelf: [String: Any]?
    )
        -> String? {
        let buttons = shelfHeader(from: shelf)?["buttons"]
            as? [[String: Any]] ?? []
        for button in buttons {
            guard let renderer = button["buttonRenderer"]
                as? [String: Any],
                renderer.digString("icon", "iconType") == "SHUFFLE"
            else {
                continue
            }
            return renderer.digString(
                "navigationEndpoint",
                "watchEndpoint",
                "params"
            )
        }
        return nil
    }

    static func shelfHeader(
        from shelf: [String: Any]?
    )
        -> [String: Any]? {
        // Current responses put the header under `headerRenderer`;
        // older ones used `header`.
        let header = shelf?["headerRenderer"] as? [String: Any]
            ?? shelf?["header"] as? [String: Any]
        return header?["shelfHeaderRenderer"] as? [String: Any]
            ?? header?["playlistShelfHeaderRenderer"] as? [String: Any]
    }

    /// Deliberately not the shelf header's own title: the server sends
    /// "Up next" there, in the request's `hl` rather than the app's language,
    /// and for a named playlist it is not the playlist's name either. Only
    /// the playlist header carries a real title; everything else falls back
    /// to our own word for a mix.
    static func extractPivotTitle(
        from section: [String: Any]
    )
        -> String {
        let header = section.digDict(
            "shelfRenderer",
            "headerRenderer",
            "playlistShelfHeaderRenderer"
        ) ?? section.digDict(
            "shelfRenderer",
            "header",
            "playlistShelfHeaderRenderer"
        )
        return simpleText(from: header?["title"])
            ?? "player.related.mix".localized
    }
}
