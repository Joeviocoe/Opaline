import Foundation

// MARK: - Shorts in the TV history feed

/// TV history hands shorts over as ordinary tiles: `watchEndpoint`, no reel
/// endpoint, no SHORTS badge, `contentType` plain VIDEO (a labelled live
/// sample of two shorts and two videos was diffed field by field). The one
/// difference is the thumbnail — a short's is a server-side crop carrying an
/// `sqp` signature, an ordinary video's is the bare `hqdefault.jpg`.
///
/// Deliberately not in `VideoRendererParserChain`: `sqp` is on nearly every
/// thumbnail elsewhere (watch pages, web feeds), so it only means anything
/// among these tiles.
extension InnertubeClient {
    /// Longest a short can be, as its duration badge reads.
    private static let maxShortMinutes = 3

    static func markingShorts(
        _ videos: [Video], fromHistory items: [[String: Any]]
    ) -> [Video] {
        let ids = croppedThumbnailIds(in: items)
        return videos.map { video in
            guard !video.isShort, ids.contains(video.id),
                  isShortDuration(video.duration) else {
                return video
            }
            var short = video
            short.isShort = true
            return short
        }
    }

    private static func croppedThumbnailIds(
        in items: [[String: Any]]
    ) -> Set<String> {
        var ids: Set<String> = []
        for item in items {
            guard let tile = item[RendererKey.tile] as? [String: Any],
                  let id = tile["contentId"] as? String,
                  let header = tile.digDict(
                      JSONKey.header, RendererKey.tileHeader
                  ),
                  let url = header.thumbnailURL(),
                  url.contains("sqp=") else {
                continue
            }
            ids.insert(id)
        }
        return ids
    }

    /// "0:16" and "1:06" are shorts, "17:07" is not; anything with an hours
    /// component certainly is not.
    private static func isShortDuration(_ duration: String?) -> Bool {
        let parts = duration?.split(separator: ":") ?? []
        guard parts.count == 2, let minutes = Int(parts[0]) else {
            return false
        }
        return minutes <= maxShortMinutes
    }
}
