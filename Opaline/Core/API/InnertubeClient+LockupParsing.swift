import Foundation

extension InnertubeClient {
    static func playlistTitle(
        from lockup: [String: Any]
    ) -> String? {
        let title = lockup.digString(
            "metadata",
            "lockupMetadataViewModel",
            JSONKey.title,
            JSONKey.content
        ) ?? ""
        return title.isEmpty ? nil : title
    }

    static func playlistThumbnailURL(
        from lockup: [String: Any]
    ) -> String? {
        let url = lockup.digString(
            "contentImage",
            "collectionThumbnailViewModel",
            "primaryThumbnail",
            "thumbnailViewModel",
            "image",
            "sources",
            0,
            JSONKey.url
        )
        return url.map(normalizeThumbnailURL)
    }

    static func playlistBadgeCount(
        from lockup: [String: Any]
    ) -> Int? {
        let text = lockup.digString(
            "contentImage",
            "collectionThumbnailViewModel",
            "primaryThumbnail",
            "thumbnailViewModel",
            "overlays",
            0,
            "thumbnailOverlayBadgeViewModel",
            "thumbnailBadges",
            0,
            "thumbnailBadgeViewModel",
            JSONKey.text
        )
        return playlistItemCount(from: text)
    }

    static func playlistItemCount(from text: String?) -> Int? {
        guard let text else {
            return nil
        }
        let digits = text.filter { $0.isNumber }
        return Int(digits)
    }

    // MARK: - Video lockup

    static func parseLockupVideo(_ lockup: [String: Any]) -> Video? {
        guard let videoId = lockup["contentId"] as? String,
              let title = playlistTitle(from: lockup)
        else { return nil }
        let thumbnail = preferredThumbnailURL(
            videoId: videoId,
            fallbackURL: lockupVideoThumbnailURL(from: lockup) ?? ""
        )
        let (duration, isLive) = lockupVideoDuration(from: lockup)
        let (viewCount, publishedAt) = lockupVideoMeta(from: lockup)
        return Video(
            id: videoId,
            title: title,
            channelId: nil,
            channelName: "",
            channelAvatarURL: nil,
            thumbnailURL: thumbnail,
            viewCount: viewCount,
            publishedAt: publishedAt,
            duration: duration,
            isLive: isLive
        )
    }

    /// Video lockups keep their thumbnail under `contentImage`
    /// (2026-07 shape) or `thumbnail` (older responses).
    private static func lockupThumbnailViewModel(
        from lockup: [String: Any]
    ) -> [String: Any]? {
        lockup.digDict("contentImage", "thumbnailViewModel")
            ?? lockup.digDict("thumbnail", "thumbnailViewModel")
    }

    private static func lockupVideoDuration(
        from lockup: [String: Any]
    ) -> (duration: String?, isLive: Bool) {
        let overlays = lockupThumbnailViewModel(from: lockup)?["overlays"]
            as? [[String: Any]] ?? []
        for overlay in overlays {
            if let badge = durationFromBadge(overlay) {
                return badge
            }
            if let ts = overlay["thumbnailOverlayTimeStatusViewModel"] as? [String: Any] {
                if (ts["style"] as? String) == "LIVE" {
                    return (nil, true)
                }
                return (ts.digString(JSONKey.text, JSONKey.content), false)
            }
        }
        return (nil, false)
    }

    private static func durationFromBadge(
        _ overlay: [String: Any]
    ) -> (duration: String?, isLive: Bool)? {
        guard let bottom = overlay["thumbnailBottomOverlayViewModel"] as? [String: Any],
              let badges = bottom["badges"] as? [[String: Any]],
              let badge = badges.first,
              let badgeVM = badge["thumbnailBadgeViewModel"] as? [String: Any],
              let text = badgeVM[JSONKey.text] as? String,
              !text.isEmpty
        else { return nil }
        return (text, false)
    }

    private static func lockupVideoMeta(
        from lockup: [String: Any]
    ) -> (viewCount: String?, publishedAt: String?) {
        let rows = lockup.digArray(
            "metadata",
            "lockupMetadataViewModel",
            "metadata",
            "contentMetadataViewModel",
            "metadataRows"
        ) ?? []
        for row in rows {
            guard let parts = row["metadataParts"] as? [[String: Any]],
                  parts.count >= 2
            else { continue }
            let texts = parts.compactMap { $0.digString(JSONKey.text, JSONKey.content) }
            if texts.count >= 2 {
                return (texts[0], texts[1])
            }
        }
        return (nil, nil)
    }

    private static func lockupVideoThumbnailURL(from lockup: [String: Any]) -> String? {
        let url = lockupThumbnailViewModel(from: lockup)?.digString(
            "image", "sources", 0, JSONKey.url
        )
        return url.map(normalizeThumbnailURL)
    }
}
