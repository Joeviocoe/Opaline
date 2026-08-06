import Foundation

/// Minimal parser for YouTube's public per-channel Atom feed
/// (`/feeds/videos.xml?channel_id=...`): extracts each entry's video id
/// and exact publish date; every other field is ignored.
enum ChannelRSSParser {
    /// nil when the document isn't parseable XML.
    static func parse(_ data: Data) -> [RSSVideoEntry]? {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return delegate.entries
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [RSSVideoEntry] = []
    private var insideEntry = false
    private var currentElement = ""
    private var videoId = ""
    private var published = ""
    private let dateFormatter = ISO8601DateFormatter()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "entry" {
            insideEntry = true
            videoId = ""
            published = ""
        }
        currentElement = elementName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideEntry else {
            return
        }
        switch currentElement {
        case "yt:videoId":
            videoId += string
        case "published":
            published += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        currentElement = ""
        guard elementName == "entry" else {
            return
        }
        insideEntry = false
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateString = published.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !id.isEmpty,
              let date = dateFormatter.date(from: dateString)
        else {
            return
        }
        entries.append(RSSVideoEntry(videoId: id, published: date))
    }
}
