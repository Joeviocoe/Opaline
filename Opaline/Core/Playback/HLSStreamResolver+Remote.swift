import Foundation

// MARK: - Remote n/sig solving (iOS 12/13 fallback)

extension HLSStreamResolver {
    static func parseRemoteSolved(data: Data?, unsolved: String) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data)
              as? [String: Any],
              let solved = json["solved"] as? [String: Any],
              let value = solved[unsolved] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// POSTs the player-JS path and the unsolved challenge to the configured
    /// solver service, which runs the EJS solver on a modern engine and
    /// returns the solved value. No video id or user data is sent. Yields nil
    /// when no endpoint is set.
    static func logRemoteOutcome(
        kind: ChallengeKind,
        solved: String?,
        since: Date
    ) {
        let ms = Int(Date().timeIntervalSince(since) * 1_000)
        AppLog.player(
            "hlsResolve: remote \(kind.rawValue)"
                + " \(solved == nil ? "failed" : "solved") in \(ms)ms"
        )
    }

    func solveRemote(
        kind: ChallengeKind,
        unsolved: String,
        jsPath: String?,
        completion: @escaping (String?) -> Void
    ) {
        guard let endpoint = AppURLs.NSolver.endpoint, let jsPath else {
            AppLog.player("hlsResolve: no remote solver configured")
            completion(nil)
            return
        }
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["jsUrl": jsPath, kind.rawValue: [unsolved]]
        ) else {
            completion(nil)
            return
        }
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON],
            body: body
        )
        AppLog.player(
            "hlsResolve: remote solving \(kind.rawValue) via \(endpoint.host ?? "")"
        )
        PlaybackProgress.step("player.status.solving")
        // Timed: this round trip is the price iOS 12 pays for not being able
        // to run the challenge locally, and a cold server makes it the whole
        // start-up cost — the log is what tells the two apart.
        let t0 = Date()
        transport.send(request, cancellationToken: nil) { result in
            let data = try? result.get().data
            let solved = Self.parseRemoteSolved(data: data, unsolved: unsolved)
            Self.logRemoteOutcome(kind: kind, solved: solved, since: t0)
            completion(solved)
        }
    }
}
