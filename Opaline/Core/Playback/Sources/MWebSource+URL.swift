import Foundation

// MARK: - Media URL query helpers

extension MWebSource {
    /// Thread-safe collector for solver results — the n/sig completions land
    /// on arbitrary queues, so mutations go through a lock instead of racing
    /// on a captured var.
    final class SolutionBox {
        private var solved: [String: String] = [:]
        private let lock = NSLock()

        func store(
            kind: HLSStreamResolver.ChallengeKind,
            unsolved: String,
            solved value: String?
        ) {
            guard let value else {
                return
            }
            lock.lock()
            solved["\(kind.rawValue)|\(unsolved)"] = value
            lock.unlock()
        }

        func value(
            kind: HLSStreamResolver.ChallengeKind, unsolved: String
        ) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return solved["\(kind.rawValue)|\(unsolved)"]
        }
    }

    /// The n/sig-solved DASH pair, ready for the pot/cver rewrite. Nil when
    /// either format's sig challenge stayed unsolved.
    static func makeStreams(
        video: DashFormatInfo, audio: DashFormatInfo, solutions: SolutionBox
    ) -> SolvedStreams? {
        guard let videoURL = playableURL(video, solutions),
              let audioURL = playableURL(audio, solutions) else {
            return nil
        }
        return SolvedStreams(
            video: video, audio: audio, videoURL: videoURL, audioURL: audioURL
        )
    }

    /// The format's URL with solved challenges applied. An unsolved `n` only
    /// throttles, so it passes through; an unsolved sig challenge returns nil.
    static func playableURL(
        _ format: DashFormatInfo, _ solutions: SolutionBox
    ) -> URL? {
        var url = format.url
        if let unsolved = nValue(of: url),
           let solved = solutions.value(kind: .nThrottle, unsolved: unsolved) {
            url = replacingN(in: url, solved: solved)
        }
        if let challenge = format.sigChallenge {
            guard let solved = solutions.value(kind: .sig, unsolved: challenge) else {
                return nil
            }
            url = appendingQuery(
                url, name: format.sigParam ?? "signature", value: solved
            )
        }
        return url
    }

    static func appendingQuery(_ url: URL, name: String, value: String) -> URL {
        guard var components = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == name }
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? url
    }

    static func nValue(of url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == "n" }?.value
    }

    static func hasQuery(_ url: URL, _ name: String) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains { $0.name == name } ?? false
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

    // MARK: - Live-manifest path params
    //
    // Live manifest URLs (manifest.googlevideo.com) encode params as path
    // segments (`/n/<value>/`), not query items. Rewrites go through plain
    // string replacement — rebuilding the path via URLComponents could
    // re-encode other segments and invalidate the `sig`.

    static func livePathN(of url: URL) -> String? {
        HLSStreamResolver.firstMatch(
            in: url.absoluteString, pattern: "/n/([^/]+)/"
        )
    }

    static func replacingLivePathN(in url: URL, solved: String?) -> URL {
        guard let solved, let unsolved = livePathN(of: url) else {
            return url
        }
        let replaced = url.absoluteString.replacingOccurrences(
            of: "/n/\(unsolved)/", with: "/n/\(solved)/"
        )
        return URL(string: replaced) ?? url
    }
}
