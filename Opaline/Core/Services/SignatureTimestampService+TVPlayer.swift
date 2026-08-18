import Foundation

// MARK: - TV player JS

extension SignatureTimestampService {
    private static let tvPathKey = "SignatureTimestamp.tvJsPath.v2"
    /// The STS the cached path was scraped beside. The timestamp we send decides
    /// which player YouTube signs the URL with, and only that player's transform
    /// answers its `n` — a path cached for longer than the timestamp it belongs
    /// to earns a 403 the next time YouTube rotates.
    private static let tvPathSTSKey = "SignatureTimestamp.tvJsPathSTS"
    private static let tvVersionKey = "SignatureTimestamp.tvClientVersion"

    /// The TV client version `youtube.com/tv` runs right now, scraped beside the
    /// player path. It goes on the media URL as `cver`, and googlevideo refuses
    /// a URL whose `cver` it does not recognise — the version carries a date and
    /// rotates weekly, so it cannot be a constant.
    static var tvClientVersion: String? {
        UserDefaults.standard.string(forKey: tvVersionKey)
    }

    static func clientVersion(in html: String) -> String? {
        guard let range = html.range(
            of: "\"INNERTUBE_CLIENT_VERSION\":\"[^\"]+\"", options: .regularExpression
        ) else {
            return nil
        }
        return String(html[range]).components(separatedBy: "\"").dropLast().last
    }

    /// Rewrites any advertised TV player path to the `ias-tcl` build, keeping
    /// the player id — that id rotates, the variant does not.
    static func tclVariant(of path: String) -> String {
        variant("tv-player-ias-tcl.vflset/tv-player-ias-tcl.js", of: path)
    }

    private static func variant(_ file: String, of path: String) -> String {
        guard let idRange = path.range(
            of: "/s/player/[^/]+/", options: .regularExpression
        ) else {
            return path
        }
        return String(path[idRange]) + file
    }

    static func playerPath(in html: String) -> String? {
        guard let range = html.range(
            of: "\"(PLAYER_JS_URL|jsUrl)\":\"(\\\\?/s\\\\?/player[^\"]+\\.js)\"",
            options: .regularExpression
        ) else {
            return nil
        }
        let match = String(html[range])
        guard let pathRange = match.range(
            of: "\\\\?/s\\\\?/player[^\"]+\\.js", options: .regularExpression
        ) else {
            return nil
        }
        return String(match[pathRange]).replacingOccurrences(of: "\\/", with: "/")
    }

    /// Path to the TV player JS, scraped from `youtube.com/tv`.
    ///
    /// The `n` challenge on a TV streaming URL has to be solved with the player
    /// that issued it: the web player's answer, and the `tv-player-es6` one the
    /// page advertises to our user agent, both earn a 403. What the television
    /// actually runs — verified from a live session's call stack — is the
    /// `tv-player-ias-tcl` build, so keep the scraped player id and swap the
    /// variant.
    func tvPlayerPath(completion: @escaping (String?) -> Void) {
        // The STS is cached and fetched before /player either way, so this waits
        // on nothing during playback.
        fetch { [weak self] sts in
            self?.tvPlayerPath(matching: sts, completion: completion)
        }
    }

    private func tvPlayerPath(matching sts: Int?, completion: @escaping (String?) -> Void) {
        let defaults = UserDefaults.standard
        let cached = defaults.string(forKey: Self.tvPathKey)
        // No timestamp to compare against means no network: whatever is cached
        // beats nothing.
        // The version is scraped from the same page, so a cached path without
        // one is a half-filled cache and worth re-reading.
        if let cached, Self.tvClientVersion != nil,
           sts == nil || defaults.integer(forKey: Self.tvPathSTSKey) == sts {
            completion(cached)
            return
        }
        scrapeTVPlayerPath(sts: sts, fallback: cached, completion: completion)
    }

    private func scrapeTVPlayerPath(
        sts: Int?,
        fallback: String?,
        completion: @escaping (String?) -> Void
    ) {
        let defaults = UserDefaults.standard
        guard let url = URL(string: AppURLs.YouTube.base + "/tv") else {
            completion(fallback)
            return
        }
        let headers = [HTTPHeader.userAgent: UserAgent.cobaltFireTV]
        transport.send(
            HTTPRequest(
                method: .get, url: url, headers: headers, isPlayback: true
            ),
            cancellationToken: nil
        ) { result in
            guard case .success(let response) = result,
                  let html = String(data: response.data, encoding: .utf8),
                  let path = Self.playerPath(in: html) else {
                AppLog.log("SigTS", "tv player path not found")
                completion(fallback)
                return
            }
            let resolved = Self.tclVariant(of: path)
            let version = Self.clientVersion(in: html)
            AppLog.log("SigTS", "tv player \(resolved) cver=\(version ?? "nil")")
            defaults.set(version, forKey: Self.tvVersionKey)
            defaults.set(resolved, forKey: Self.tvPathKey)
            defaults.set(sts ?? 0, forKey: Self.tvPathSTSKey)
            completion(resolved)
        }
    }
}
