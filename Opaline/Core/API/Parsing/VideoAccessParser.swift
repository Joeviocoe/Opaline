import Foundation

/// Reads whether a video is members-only or paid from a raw list item.
///
/// YouTube marks both with a badge style string rather than a flag, and
/// where that badge sits depends on the renderer: `videoRenderer`,
/// `compactVideoRenderer` and `gridVideoRenderer` carry a `badges` array of
/// `metadataBadgeRenderer`s next to the title, a `richItemRenderer` wraps
/// one of those, and a `lockupViewModel` puts a `badgeViewModel` inside its
/// metadata rows. The styles are the stable part:
///
///   `BADGE_STYLE_TYPE_MEMBERS_ONLY` / `BADGE_MEMBERS_ONLY`
///   `BADGE_STYLE_TYPE_YPC`         / `BADGE_YPC`   (paid content)
///
/// So rather than teach every parser its own path, this walks the item for
/// any `style` or `badgeStyle` value with one of those stems. The walk is
/// bounded in depth and skips the thumbnail subtree, which is where the
/// bulk of an item's nodes live and where these badges never are.
///
/// The depth bound has to clear the lockup, which is the deepest of them —
/// checked against a live channel Videos tab on 2026-11-15:
///
///   richItemRenderer / content / lockupViewModel / metadata /
///   lockupMetadataViewModel / metadata / contentMetadataViewModel /
///   metadataRows / [1] / badges / [0] / badgeViewModel / badgeStyle
///
/// That is thirteen levels. A bound of eight, the first guess, silently
/// missed every members-only video on every channel page.
enum VideoAccessParser {
    private static let styleKeys: Set<String> = ["style", "badgeStyle"]
    private static let skippedKeys: Set<String> = [
        "thumbnail", "contentImage", "thumbnails", "menu",
        "navigationEndpoint", "onTap", "onSelectCommand",
        "channelThumbnailSupportedRenderers", "avatar"
    ]
    private static let maxDepth = 20

    static func access(in item: [String: Any]) -> Video.Access {
        var found: Video.Access = .free
        scan(item, depth: 0, into: &found)
        return found
    }

    private static func scan(
        _ node: Any, depth: Int, into found: inout Video.Access
    ) {
        guard found == .free, depth < maxDepth else {
            return
        }
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if styleKeys.contains(key), let style = value as? String {
                    if let access = access(fromStyle: style) {
                        found = access
                        return
                    }
                    continue
                }
                guard !skippedKeys.contains(key) else {
                    continue
                }
                scan(value, depth: depth + 1, into: &found)
            }
        } else if let array = node as? [Any] {
            for value in array {
                scan(value, depth: depth + 1, into: &found)
            }
        }
    }

    private static func access(fromStyle style: String) -> Video.Access? {
        if style.hasSuffix("MEMBERS_ONLY") {
            return .membersOnly
        }
        if style.hasSuffix("_YPC") {
            return .paid
        }
        return nil
    }
}
