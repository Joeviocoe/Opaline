import Foundation

// MARK: - Search suggestions

extension InnertubeClient {
    private static func parseSuggestions(_ data: Data) -> [String] {
        // The endpoint may reply in Latin-1 depending on locale;
        // JSONSerialization needs UTF-8, so re-encode when needed.
        var jsonData = data
        if String(data: data, encoding: .utf8) == nil,
           let latin = String(data: data, encoding: .isoLatin1),
           let reencoded = latin.data(using: .utf8) {
            jsonData = reencoded
        }
        guard let root = try? JSONSerialization.jsonObject(
            with: jsonData
        ),
            let array = root as? [Any],
            array.count > 1,
            let suggestions = array[1] as? [String]
        else {
            return []
        }
        return suggestions
    }

    /// Autocomplete via the public suggest endpoint.
    /// Response shape: `["<query>", ["s1", "s2", ...], ...]`.
    func fetchSearchSuggestions(
        query: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let url = AppURLs.Suggest.searchURL(query: query)
        else {
            completion(.success([]))
            return
        }
        api.get(
            url: url,
            cancellationToken: cancellationToken
        ) { result in
            completion(result.map(Self.parseSuggestions))
        }
    }
}
