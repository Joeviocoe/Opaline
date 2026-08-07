import Foundation

/// Channel identity as the watch page's owner block carries it.
struct OwnerInfo {
    let channelId: String?
    let title: String?
    let avatarURL: String?
}

extension InnertubeClient {
    // Extract channelId + name + avatarURL from the owner renderers.
    static func extractOwnerInfo(
        _ json: [String: Any]
    ) -> OwnerInfo {
        // A watch page carries the same owner two or three times and only
        // one copy holds the browseId, in no fixed order — so the fields are
        // merged across all of them. Reading them off the first renderer that
        // matched dropped the channelId about half the time, and with it the
        // whole ChannelInfo (verified against a live Shorts feed).
        var info = OwnerInfo(channelId: nil, title: nil, avatarURL: nil)
        var anyTitle: String?
        for owner in allOwnerRenderers(json) {
            let title = simpleText(from: owner["title"])
            anyTitle = anyTitle ?? title
            info = OwnerInfo(
                channelId: info.channelId ?? firstMatchingBrowseId(in: owner)
                    .flatMap { $0.isEmpty ? nil : $0 },
                // The renderer also wraps the player's "Channel" button,
                // whose title is that literal word rather than the channel's
                // name. Only the real owner carries a subscriber count.
                title: info.title ?? (owner["subscriberCountText"] == nil
                    ? nil : title),
                avatarURL: info.avatarURL ?? extractThumbnailURL(
                    from: owner["thumbnail"]
                )
            )
        }
        return OwnerInfo(
            channelId: info.channelId,
            title: info.title ?? anyTitle,
            avatarURL: info.avatarURL
        )
    }

    static func allOwnerRenderers(
        _ value: Any
    ) -> [[String: Any]] {
        let names = [
            "slimOwnerRenderer",
            "videoOwnerRenderer",
            "ownerRenderer",
            "channelThumbnailWithLinkRenderer"
        ]
        if let dict = value as? [String: Any] {
            var found: [[String: Any]] = []
            for (key, child) in dict {
                if names.contains(key), let owner = child as? [String: Any] {
                    found.append(owner)
                } else {
                    found += allOwnerRenderers(child)
                }
            }
            return found
        }
        if let array = value as? [Any] {
            return array.flatMap { allOwnerRenderers($0) }
        }
        return []
    }
}
