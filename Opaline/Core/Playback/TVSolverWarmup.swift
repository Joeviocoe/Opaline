import Foundation

/// Asks the solver service for a throwaway `n` so the real one is instant.
///
/// The service builds a solver per TV player, which costs it a 2.5 MB download
/// and a parse — a couple of seconds for a player it has not seen, against the
/// eight the client waits before giving up and sending the URL unsolved (403).
/// Its own warm-up only knows the player `youtube.com/tv` advertises to *it*,
/// and that is not always the one advertised to the phone, so ask for ours.
///
/// Deliberately does not go through `HLSStreamResolver.solveN`: on iOS 14+ that
/// tries the on-device solver first, which would download the same 2.5 MB to the
/// phone and fail on it (the EJS extractor finds nothing in a TV build), and it
/// reports playback progress, which has no business firing outside playback.
enum TVSolverWarmup {
    /// Shaped like a real challenge; the answer is thrown away.
    private static let probe = "opalinewarmup12345678"
    private static var didWarm = false

    /// Only the signed-in TV path solves `n`: android_vr URLs carry none, and
    /// anonymously TV is not reachable at all.
    private static var isUseful: Bool {
        guard OAuthClient.shared.isSignedIn else {
            return false
        }
        switch PlaybackSource.selected {
        case .auto, .tv:
            return true
        case .visionOS, .androidVR, .progressive, .mwebPot:
            return false
        }
    }

    /// Call once the app is idle — the home feed settling is the signal for it.
    static func warmIfNeeded(transport: HTTPTransport = ServiceContainer.transport) {
        guard !didWarm, isUseful, let endpoint = AppURLs.NSolver.endpoint else {
            return
        }
        didWarm = true
        SignatureTimestampService.shared.tvPlayerPath { jsPath in
            guard let jsPath else {
                return
            }
            send(to: endpoint, jsPath: jsPath, transport: transport)
        }
    }

    private static func send(to endpoint: URL, jsPath: String, transport: HTTPTransport) {
        guard let body = try? JSONSerialization.data(
            withJSONObject: ["jsUrl": jsPath, "n": [probe]]
        ) else {
            return
        }
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON],
            body: body,
            // Longer than playback's eight seconds on purpose: nobody is
            // waiting, and a build that outlives our request still leaves the
            // service warm.
            timeout: 30,
            isPlayback: true
        )
        let started = Date()
        transport.send(request, cancellationToken: nil) { result in
            let ms = Int(Date().timeIntervalSince(started) * 1_000)
            let solved = HLSStreamResolver.parseRemoteSolved(
                data: try? result.get().data, unsolved: probe
            )
            AppLog.player(
                "tvWarmup: solver \(solved == nil ? "did not answer" : "warm") in \(ms)ms"
            )
        }
    }
}
