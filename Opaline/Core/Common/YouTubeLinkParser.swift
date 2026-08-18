import Foundation

/// Pure `URL` → video-id extraction. No networking, no app dependencies —
/// used by `AppDelegate`'s `application(_:open:options:)` and mirrored by
/// `scripts/check_youtube_link_parser.swift` for a runnable check.
enum YouTubeLinkParser {
    /// Path prefixes that carry the video id as the next path component,
    /// e.g. `/shorts/VIDEOID`.
    private static let idPathKeywords: Set<String> = ["shorts", "live", "embed"]

    static func videoId(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else {
            return nil
        }
        if url.scheme?.lowercased() == "ytlite" {
            // ytlite://watch?v=VIDEOID — host is "watch" for this shape.
            return queryValue(url, name: "v")
        }
        guard isYouTubeHost(host) else {
            return nil
        }
        if host == "youtu.be" {
            return pathComponents(url).first
        }
        let components = pathComponents(url)
        if let keyword = components.first, idPathKeywords.contains(keyword) {
            return components.count > 1 ? components[1] : nil
        }
        if url.path.isEmpty || url.path == "/watch" {
            return queryValue(url, name: "v")
        }
        return nil
    }

    /// Seconds a link asks playback to start at — `?t=87`, `?t=1m30s`, or the
    /// `start=` an embed carries. Nil when the link has no timecode.
    static func startSeconds(from url: URL) -> Double? {
        guard let raw = queryValue(url, name: "t")
            ?? queryValue(url, name: "start")
        else {
            return nil
        }
        if let plain = Double(raw) {
            return plain > 0 ? plain : nil
        }
        return unitTimecodeSeconds(raw)
    }

    /// `1h2m3s` and its shorter forms, the shape YouTube's own share sheet
    /// writes for anything past a minute.
    private static func unitTimecodeSeconds(_ raw: String) -> Double? {
        let units: [Character: Double] = ["h": 3_600, "m": 60, "s": 1]
        var total = 0.0
        var digits = ""
        for character in raw.lowercased() {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let unit = units[character], let value = Double(digits) else {
                return nil
            }
            total += value * unit
            digits = ""
        }
        guard digits.isEmpty, total > 0 else {
            return nil
        }
        return total
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    private static func pathComponents(_ url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    private static func queryValue(_ url: URL, name: String) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems
        else {
            return nil
        }
        return items.first { $0.name == name }?.value
    }
}
