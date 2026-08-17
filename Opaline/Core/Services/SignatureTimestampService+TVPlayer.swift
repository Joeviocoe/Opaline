import Foundation

// MARK: - TV player JS

extension SignatureTimestampService {
    private static let tvPathKey = "SignatureTimestamp.tvJsPath.v2"

    /// Rewrites any advertised TV player path to the `ias-tcl` build, keeping
    /// the player id — that id rotates, the variant does not.
    static func tclVariant(of path: String) -> String {
        guard let idRange = path.range(
            of: "/s/player/[^/]+/", options: .regularExpression
        ) else {
            return path
        }
        return String(path[idRange]) + "tv-player-ias-tcl.vflset/tv-player-ias-tcl.js"
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
        if let cached = UserDefaults.standard.string(forKey: Self.tvPathKey) {
            completion(cached)
            return
        }
        guard let url = URL(string: AppURLs.YouTube.base + "/tv") else {
            completion(nil)
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
                completion(nil)
                return
            }
            let resolved = Self.tclVariant(of: path)
            AppLog.log("SigTS", "tv player \(resolved)")
            UserDefaults.standard.set(resolved, forKey: Self.tvPathKey)
            completion(resolved)
        }
    }
}
