import UIKit

/// Builds tappable `NSAttributedString`s for URLs (via `NSDataDetector`) and,
/// optionally, video timestamps (via a small regex), plus the shared
/// `UITextView` setup used to render them without hand-rolled tap hit-testing.
///
/// Timestamp matching (`includeTimestamps == true`): matches `1:23`,
/// `12:34`, `1:02:03`, optionally wrapped in `()`/`[]`. Does NOT match bare
/// numbers (`123`), 3+ digit seconds (`12:345`), or a timestamp glued to a
/// longer digit run (`112:34`).
enum LinkifiedText {
    /// Timestamp taps are encoded as `ytlite-seek://<seconds>` so they can
    /// ride the same `UITextView` link-tap delegate as real links.
    static let seekScheme = "ytlite-seek"

    private static let timestampRegex = try? NSRegularExpression(
        pattern: #"(?<!\d)[(\[]?(\d{1,2}:)?[0-5]?\d:[0-5]\d[)\]]?(?!\d)"#
    )

    static func attributedString(
        from text: String,
        font: UIFont,
        color: UIColor,
        includeTimestamps: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
        let fullRange = NSRange(text.startIndex..., in: text)
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) {
            for match in detector.matches(in: text, range: fullRange) {
                guard let url = match.url else {
                    continue
                }
                result.addAttribute(.link, value: url, range: match.range)
            }
        }
        if includeTimestamps {
            addTimestampLinks(to: result, text: text, fullRange: fullRange)
        }
        return result
    }

    private static func addTimestampLinks(
        to result: NSMutableAttributedString,
        text: String,
        fullRange: NSRange
    ) {
        guard let regex = timestampRegex else {
            return
        }
        for match in regex.matches(in: text, range: fullRange) {
            var alreadyLinked = false
            result.enumerateAttribute(.link, in: match.range) { value, _, stop in
                if value != nil {
                    alreadyLinked = true
                    stop.pointee = true
                }
            }
            guard !alreadyLinked, let range = Range(match.range, in: text) else {
                continue
            }
            let raw = String(text[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
            guard let seconds = seconds(from: raw),
                  let url = URL(string: "\(seekScheme)://\(seconds)")
            else {
                continue
            }
            result.addAttribute(.link, value: url, range: match.range)
        }
    }

    private static func seconds(from timestamp: String) -> Int? {
        let parts = timestamp.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else {
            return nil
        }
        var total = 0
        var multiplier = 1
        for part in parts.reversed() {
            total += part * multiplier
            multiplier *= 60
        }
        return total
    }

    /// Decodes a timestamp URL produced above; `nil` for any other URL.
    static func seekSeconds(from url: URL) -> Int? {
        guard url.scheme == seekScheme else {
            return nil
        }
        return url.host.flatMap(Int.init)
    }

    /// Common tap handling: seek for a timestamp URL, otherwise hand the
    /// URL to the system opener. Always returns `false` — the tap is fully
    /// handled here rather than by UIKit's default link behavior.
    @discardableResult
    static func handleTap(url: URL, seek: ((Int) -> Void)? = nil) -> Bool {
        if let seconds = seekSeconds(from: url), let seek {
            seek(seconds)
        } else {
            UIApplication.shared.open(url)
        }
        return false
    }

    /// Shared non-scrolling, zero-inset `UITextView` setup for the three
    /// call sites that render linkified text.
    static func configure(_ textView: UITextView) {
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
    }
}
