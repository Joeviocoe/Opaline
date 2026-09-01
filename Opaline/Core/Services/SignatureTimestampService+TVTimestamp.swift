import Foundation

// MARK: - The TV player's own signature timestamp

extension SignatureTimestampService {
    private static let tvStsKey = "SignatureTimestamp.tvValue"
    private static let tvStsPathKey = "SignatureTimestamp.tvValuePath"

    /// The timestamp belonging to the TV player we solve `n` with.
    ///
    /// Not derived from the site-wide one: that is scraped from the desktop page
    /// and cached for a week, while the TV player rotates on its own schedule.
    /// When they drifted apart on 2026-08-17 YouTube signed the media URL with
    /// the player the *timestamp* named and we descrambled with the player
    /// `/tv` advertised, and every segment came back 403 — with a correct `n`,
    /// which is what made it look like the solver's fault. The solver already
    /// holds the player file, so it reads the timestamp out of that same file
    /// and the two cannot disagree.
    func tvSignatureTimestamp(completion: @escaping (Int?) -> Void) {
        tvPlayerPath { [weak self] jsPath in
            guard let self = self, let jsPath = jsPath else {
                completion(nil)
                return
            }
            let defaults = UserDefaults.standard
            if defaults.string(forKey: Self.tvStsPathKey) == jsPath {
                let cached = defaults.integer(forKey: Self.tvStsKey)
                if cached > 0 {
                    completion(cached)
                    return
                }
            }
            fetchTVTimestamp(jsPath: jsPath, completion: completion)
        }
    }

    private func fetchTVTimestamp(jsPath: String, completion: @escaping (Int?) -> Void) {
        guard let url = AppURLs.NSolver.timestamp,
              let body = try? JSONSerialization.data(withJSONObject: ["jsUrl": jsPath]) else {
            completion(nil)
            return
        }
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON],
            body: body,
            timeout: 8,
            isPlayback: true
        )
        transport.send(request, cancellationToken: nil) { result in
            guard case .success(let response) = result,
                  let json = try? JSONSerialization.jsonObject(with: response.data)
                  as? [String: Any],
                  let sts = json["sts"] as? Int, sts > 0 else {
                AppLog.log("SigTS", "tv timestamp not read for \(jsPath)")
                completion(nil)
                return
            }
            AppLog.log("SigTS", "tv signatureTimestamp=\(sts)")
            let defaults = UserDefaults.standard
            defaults.set(sts, forKey: Self.tvStsKey)
            defaults.set(jsPath, forKey: Self.tvStsPathKey)
            completion(sts)
        }
    }
}
