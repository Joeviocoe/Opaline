import Foundation

// MARK: - Throttling signature on the SABR URL

extension SABRDelivery {
    /// What a television puts on its media URL that the response's own URL does
    /// not: read off a live TV session. `rn` is added per request by
    /// `SABRFetcher`; `pot` is on none of them — the token goes in the request
    /// body only.
    static func televisionParams(_ url: URL, cpn: String) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = (parts.queryItems ?? []).filter { $0.name != "pot" }
        items.append(URLQueryItem(name: "cpn", value: cpn))
        items.append(URLQueryItem(name: "alr", value: "yes"))
        parts.queryItems = items
        return parts.url ?? url
    }

    /// The TV client's streaming URL carries an `n` throttling challenge that
    /// the anonymous clients' do not: unsolved, googlevideo answers 403 before the SABR
    /// protocol says anything. Solve it with the player the timestamp named —
    /// `tvPlayerPath` and `tvSignatureTimestamp` read the pair out of the same
    /// file, and a mismatched pair is refused exactly like an unsolved `n`.
    ///
    /// Anything without an `n` passes straight through, so this costs the
    /// anonymous path nothing.
    static func solvingThrottle(
        _ url: URL,
        resolver: HLSStreamResolver = .shared,
        completion: @escaping (URL) -> Void
    ) {
        guard let unsolved = StreamURLParams.nValue(of: url) else {
            completion(url)
            return
        }
        SignatureTimestampService.shared.tvPlayerPath { jsPath in
            resolver.solveN(unsolved: unsolved, jsPath: jsPath) { solved in
                guard let solved else {
                    AppLog.player("sabr: n solve failed, sending the URL as-is")
                    completion(url)
                    return
                }
                AppLog.player("sabr: n solved")
                completion(StreamURLParams.replacingN(in: url, solved: solved))
            }
        }
    }
}
