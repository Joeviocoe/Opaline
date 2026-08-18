import Foundation

/// Reads and rewrites the query parameters of a signed googlevideo URL.
///
/// The throttling answer (`n`) is the only one that has to be replaced after
/// the URL is minted: the solver returns a value that the CDN checks before it
/// serves a single byte.
enum StreamURLParams {
    static func nValue(of url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "n" }?.value
    }

    static func replacingN(in url: URL, solved: String) -> URL {
        guard var components = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        var items = components.queryItems ?? []
        if let index = items.firstIndex(where: { $0.name == "n" }) {
            items[index] = URLQueryItem(name: "n", value: solved)
        }
        components.queryItems = items
        return components.url ?? url
    }
}
