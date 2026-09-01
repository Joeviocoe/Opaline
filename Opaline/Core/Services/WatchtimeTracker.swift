import Foundation

/// Records YouTube watch history by pinging
/// playbackTracking URLs from an authenticated TV player
/// response, using the same parameters as yt-dlp
/// --mark-watched.
final class WatchtimeTracker {
    private static let pingInterval: TimeInterval = 15
    /// How often the position actually goes to YouTube. The local resume
    /// position still moves on every tick because that costs nothing, but a
    /// two-hour video woke the radio 488 times to report a position the server
    /// does not keep at that resolution.
    private static let reportInterval: TimeInterval = 60
    // Client playback nonce — YouTube dedupes stats by it, so a
    // fresh value is required per playback or history entries for
    // subsequent videos (autoplay/related) are silently dropped.
    private var cpn: String = PlaybackNonce.make()
    private let transport: HTTPTransport
    private var pingTimer: Timer?
    private var urls: WatchtimeURLs?
    private var videoId: String?
    private var sessionStart: Date?
    private var lastPingedPosition: TimeInterval?
    private var lastReported: Date?

    /// Provides current playback position (seconds).
    /// Set by the host view controller before or after start().
    var timeProvider: (() -> TimeInterval)?
    /// Provides the item's duration (seconds), for the local
    /// progress fraction. Set alongside `timeProvider`.
    var durationProvider: (() -> TimeInterval)?

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    func start(videoId: String, urls: WatchtimeURLs) {
        stop()
        cpn = PlaybackNonce.make()
        self.videoId = videoId
        self.urls = urls
        sessionStart = Date()
        sendPlaybackPing(urls: urls)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.pingTimer = Timer.scheduledTimer(
                withTimeInterval: Self.pingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.sendWatchtimePing()
            }
        }
        AppLog.log("Watchtime", "tracker started \(videoId)")
    }

    func stop() {
        if urls != nil {
            sendFinalPing()
        }
        pingTimer?.invalidate()
        pingTimer = nil
        urls = nil
        videoId = nil
        sessionStart = nil
        lastPingedPosition = nil
        lastReported = nil
    }

    // MARK: - Private

    private func currentPosition() -> TimeInterval {
        timeProvider?() ?? 0
    }

    /// Mirrors the position we just reported into the local store, so
    /// reopening the video resumes where this device left off instead
    /// of where the server's last sync thought it was.
    private func recordLocalProgress(_ position: TimeInterval) {
        guard let videoId = videoId,
              let duration = durationProvider?(),
              duration > 0, position > 0
        else {
            return
        }
        WatchProgressStore.shared.setLocalFraction(
            videoId: videoId,
            fraction: min(position / duration, 1)
        )
    }

    private func sendPlaybackPing(urls: WatchtimeURLs) {
        let pos = currentPosition()
        let extra = "ver=2&cpn=\(cpn)&cmt=\(fmt(pos))&el=detailpage"
        fire(baseURL: urls.playbackURL, extra: extra)
    }

    private func sendWatchtimePing() {
        guard let urls = urls else {
            return
        }
        let pos = currentPosition()
        // A paused video is still a loaded video, and the timer keeps firing
        // for as long as the screen is open — an app left on a pause overnight
        // was reporting the same second four times a minute. Nothing to report
        // means nothing to send.
        guard pos != lastPingedPosition else {
            return
        }
        lastPingedPosition = pos
        recordLocalProgress(pos)
        // Whatever is not reported now is carried by the next ping or by the
        // final one on close: each carries the absolute position, not a delta.
        if let last = lastReported, Date().timeIntervalSince(last) < Self.reportInterval {
            return
        }
        lastReported = Date()
        let extra = "ver=2&cpn=\(cpn)"
            + "&cmt=\(fmt(pos))&el=detailpage"
            + "&st=0&et=\(fmt(pos))"
        fire(baseURL: urls.watchtimeURL, extra: extra)
        AppLog.log(
            "Watchtime",
            "watchtime ping sent pos=\(Int(pos))s"
        )
    }

    private func sendFinalPing() {
        guard let urls = urls else {
            return
        }
        let pos = currentPosition()
        guard pos > 0 else {
            return
        }
        recordLocalProgress(pos)
        let extra = "ver=2&cpn=\(cpn)"
            + "&cmt=\(fmt(pos))&el=detailpage"
            + "&st=0&et=\(fmt(pos))"
        fire(baseURL: urls.watchtimeURL, extra: extra)
        AppLog.log(
            "Watchtime",
            "final ping pos=\(Int(pos))s"
        )
    }

    private func fmt(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", max(0, seconds))
    }

    private func fire(baseURL: String, extra: String) {
        let sep = baseURL.contains("?") ? "&" : "?"
        let urlStr = baseURL + sep + extra
        guard let url = URL(string: urlStr) else {
            return
        }
        OAuthClient.shared.validToken { [weak self] result in
            var headers: [String: String] = [:]
            if case let .success(token) = result {
                headers[HTTPHeader.authorization] = "Bearer \(token)"
            }
            self?.transport.send(
                HTTPRequest(method: .get, url: url, headers: headers),
                cancellationToken: nil
            ) { result in
                let code = (try? result.get().status) ?? 0
                AppLog.log("Watchtime", "ping response \(code)")
            }
        }
    }
}
