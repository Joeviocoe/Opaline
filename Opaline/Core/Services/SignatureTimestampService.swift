import Foundation

/// Fetches and caches the YouTube player signatureTimestamp (STS).
/// Required for TVHTML5 /player requests to return playbackTracking URLs.
/// Extracted from YouTube's ytcfg ("STS":NNNNN) — one HTTP request,
/// no player JS parsing needed. Value changes ~weekly.
final class SignatureTimestampService {
    static let shared = SignatureTimestampService()

    /// Path to the player JS the cached STS came from. The n-solver needs the
    /// SAME player the timestamp belongs to — scraping them from one response
    /// is what keeps them in step.
    private(set) var jsPath: String?

    private let tsKey = "SignatureTimestamp.value"
    private let jsPathKey = "SignatureTimestamp.jsPath"
    private let dateKey = "SignatureTimestamp.fetchedAt"
    private let ttl: TimeInterval = 7 * 24 * 3_600
    private let queue = DispatchQueue(
        label: "com.ytvlite.sig-ts",
        attributes: .concurrent
    )

    let transport: HTTPTransport

    private var _cached: Int?
    private var cached: Int? {
        get { queue.sync { _cached } }
        set { queue.async(flags: .barrier) { self._cached = newValue } }
    }

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
        loadFromDefaults()
    }

    func fetch(completion: @escaping (Int?) -> Void) {
        if let ts = cached {
            completion(ts)
            return
        }
        fetchFromNetwork(completion: completion)
    }

    // MARK: - Private

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        guard let ts = defaults.object(forKey: tsKey) as? Int,
              let date = defaults.object(forKey: dateKey) as? Date,
              Date().timeIntervalSince(date) < ttl
        else {
            return
        }
        _cached = ts
        jsPath = defaults.string(forKey: jsPathKey)
    }

    private func saveToDefaults(_ ts: Int) {
        let defaults = UserDefaults.standard
        defaults.set(ts, forKey: tsKey)
        defaults.set(Date(), forKey: dateKey)
        defaults.set(jsPath, forKey: jsPathKey)
    }

    /// `"jsUrl":"/s/player/<hash>/tv-player-es6.vflset/tv-player-es6.js"` —
    /// the TV page names its player `tv-player-es6.js`, the web one `base.js`,
    /// so match the path rather than a fixed file name.

    private func fetchFromNetwork(
        completion: @escaping (Int?) -> Void
    ) {
        // YouTube embeds signatureTimestamp as "STS":NNNNN in ytcfg
        // on both the main page and /tv — one request is enough.
        let sources = [
            "https://www.youtube.com/",
            "https://www.youtube.com/tv"
        ]
        fetchSTS(from: sources, index: 0, completion: completion)
    }

    private func fetchSTS(
        from sources: [String],
        index: Int,
        completion: @escaping (Int?) -> Void
    ) {
        guard index < sources.count,
              let url = URL(string: sources[index])
        else {
            AppLog.log("SigTS", "fetch failed — no STS found")
            completion(nil)
            return
        }
        transport.send(
            HTTPRequest(method: .get, url: url, isPlayback: true),
            cancellationToken: nil
        ) { [weak self] result in
            guard let self else {
                completion(nil)
                return
            }
            if case .success(let response) = result,
               let html = String(data: response.data, encoding: .utf8),
               let ts = self.extractSTS(from: html) {
                self.store(ts: ts, html: html)
                completion(ts)
            } else {
                self.fetchSTS(
                    from: sources,
                    index: index + 1,
                    completion: completion
                )
            }
        }
    }

    private func store(ts: Int, html: String) {
        jsPath = Self.playerPath(in: html)
        AppLog.log("SigTS", "signatureTimestamp=\(ts) jsPath=\(jsPath ?? "nil")")
        cached = ts
        saveToDefaults(ts)
    }

    private func extractSTS(from html: String) -> Int? {
        for pattern in ["\"STS\":(\\d+)", "\"sts\":(\\d+)"] {
            guard let range = html.range(
                of: pattern,
                options: .regularExpression
            ) else {
                continue
            }
            let matched = String(html[range])
            if let last = matched.components(
                separatedBy: ":"
            ).last, let ts = Int(last) {
                return ts
            }
        }
        return nil
    }
}
