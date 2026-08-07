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
        // The same renderer name also wraps the player's "Channel" button,
        // whose title is that literal word rather than the channel's name.
        // The real owner is the one carrying a subscriber count, so it wins.
        let owners = allOwnerRenderers(json).sorted {
            ($0["subscriberCountText"] != nil ? 0 : 1)
                < ($1["subscriberCountText"] != nil ? 0 : 1)
        }
        for owner in owners {
            let chId = firstMatchingBrowseId(in: owner)
                .flatMap { $0.isEmpty ? nil : $0 }
            let title = simpleText(from: owner["title"])
            let avatarURL = extractThumbnailURL(
                from: owner["thumbnail"]
            )
            if chId != nil || avatarURL != nil {
                return OwnerInfo(
                    channelId: chId, title: title, avatarURL: avatarURL
                )
            }
        }
        return OwnerInfo(channelId: nil, title: nil, avatarURL: nil)
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
