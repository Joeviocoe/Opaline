// swiftlint:disable:this file_name
import Foundation

// MARK: - TileVideoRendererParser

/// Handles {"tileRenderer": {...}} — used by TV/TVHTML5 client responses.
struct TileVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let tile = item[RendererKey.tile] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseTileRenderer(tile)
    }
}

// MARK: - DirectVideoRendererParser

/// Handles {"videoRenderer": {...}} — used by WEB client browse/search responses.
struct DirectVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item[RendererKey.video] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseWebVideoRenderer(vr)
    }
}

// MARK: - CompactVideoRendererParser

/// Handles {"compactVideoRenderer": {...}} — used in continuation and related responses.
struct CompactVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item[RendererKey.compactVideo] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseWebVideoRenderer(vr)
    }
}

// MARK: - GridVideoRendererParser

/// Handles {"gridVideoRenderer": {...}} — used by WEB channel tab grids.
struct GridVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item["gridVideoRenderer"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseGridVideoRenderer(vr)
    }
}

// MARK: - RichItemVideoRendererParser

/// WEB home/subscription feed richItemRenderer parser.
struct RichItemVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let vr = item.digDict(
            RendererKey.richItem, JSONKey.content, RendererKey.video
        )
        else { return nil }
        return InnertubeClient.parseWebVideoRenderer(vr)
    }
}

// MARK: - LockupViewModelVideoParser

/// Handles {"lockupViewModel": {...}} — new YouTube channel grid format.
///
/// A lockup also carries playlists and channels, and there `contentId` is a
/// playlistId/channelId rather than a videoId — search returns 16 of those
/// per page. Only video lockups may become a `Video`; playlist lockups go
/// through `parseLockupPlaylist`. Older responses omit `contentType` and
/// only ever carried videos.
struct LockupViewModelVideoParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let lockup = item["lockupViewModel"] as? [String: Any]
        else { return nil }
        let type = lockup["contentType"] as? String
            ?? "LOCKUP_CONTENT_TYPE_VIDEO"
        guard type == "LOCKUP_CONTENT_TYPE_VIDEO" else {
            return nil
        }
        return InnertubeClient.parseLockupVideo(lockup)
    }
}

// MARK: - RadioRendererParser

/// Handles {"radioRenderer": {...}} — radio mix / playlist items.
struct RadioRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let rr = item["radioRenderer"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parseRadioRenderer(rr)
    }
}

// MARK: - PlaylistRendererParser

/// Handles {"playlistRenderer": {...}} — inline playlist items.
struct PlaylistRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        guard let pr = item["playlistRenderer"] as? [String: Any]
        else { return nil }
        return InnertubeClient.parsePlaylistRenderer(pr)
    }
}

// MARK: - ReelItemVideoRendererParser

/// Handles `reelItemRenderer` (YouTube Shorts) — appears as a direct item or
/// wrapped inside `richItemRenderer/content/reelItemRenderer`.
struct ReelItemVideoRendererParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        let ri = item["reelItemRenderer"] as? [String: Any]
            ?? item.digDict(RendererKey.richItem, JSONKey.content, "reelItemRenderer")
        guard let ri = ri else {
            return nil
        }
        return InnertubeClient.parseReelItem(ri)
    }
}

// MARK: - ShortsLockupVideoParser

/// Handles `shortsLockupViewModel` — the renderer that supplanted
/// `reelItemRenderer` for Shorts grids (search, channel Shorts tab, shelves).
struct ShortsLockupVideoParser: VideoRendererParser {
    func video(from item: [String: Any]) -> Video? {
        let lockup = item["shortsLockupViewModel"] as? [String: Any]
            ?? item.digDict(
                RendererKey.richItem, JSONKey.content, "shortsLockupViewModel"
            )
        guard let lockup = lockup else {
            return nil
        }
        return InnertubeClient.parseShortsLockup(lockup)
    }
}
