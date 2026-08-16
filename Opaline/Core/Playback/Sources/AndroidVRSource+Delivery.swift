import Foundation
import QuartzCore

// MARK: - Choosing how the bytes arrive

extension AndroidVRSource {
    /// Preferred delivery first, fallback second.
    private static func deliveryOrder(
        for info: DirectPlaybackInfo,
        transport: HTTPTransport,
        client: DirectPlaybackClient
    ) -> (StreamDelivery, StreamDelivery?) {
        let range = LegacyRangeDelivery(client: client)
        // Pinned by the user: no fallback, so a failure stays visible instead
        // of being quietly papered over by the other delivery.
        switch StreamDeliveryPreference.selected {
        case .byteRange:
            AppLog.player("delivery: range (pinned, no fallback)")
            return (range, nil)
        case .sabrOnly:
            AppLog.player("delivery: sabr (pinned, no fallback)")
            return (SABRDelivery(transport: transport, client: client), nil)
        case .automatic:
            break
        }
        guard SABRDelivery.canServe(info) else {
            AppLog.player("delivery: range only — response carries no SABR stream")
            return (range, nil)
        }
        // A response whose formats carry no URL can only be played over SABR —
        // falling back to byte ranges would fetch a URL that does not exist.
        // Otherwise byte ranges stay the default, being the cheaper path and
        // the one with years of mileage, with SABR held in reserve.
        let hasStreamURLs = info.dashVideoFormat?.hasDirectURL ?? false
        let sabr = SABRDelivery(transport: transport, client: client)
        guard hasStreamURLs else {
            AppLog.player("delivery: sabr only — the response carries no stream URLs")
            return (sabr, nil)
        }
        AppLog.player("delivery: range first, sabr in reserve")
        return (range, sabr)
    }

    /// Lets go of the active delivery — for SABR that takes down its session
    /// and loopback server, which otherwise live as long as the source does.
    func releaseDelivery() {
        delivery = nil
    }

    /// Builds playback for a video/audio pair through whichever delivery suits
    /// the response, falling back to the other one if the first cannot serve it.
    ///
    /// The choice is made from what the response actually carries rather than
    /// from a setting: formats with URLs play over byte ranges, and a response
    /// without them plays over SABR. That is the whole point of splitting
    /// delivery out — if YouTube stops handing out stream URLs, as it already
    /// did for `hlsManifestUrl` in July, playback moves across on its own.
    func deliver(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let (first, second) = Self.deliveryOrder(
            for: request.info, transport: transport, client: client
        )
        delivery = first
        let started = CACurrentMediaTime()
        first.prepare(request) { [weak self] result in
            let elapsed = (CACurrentMediaTime() - started) * 1_000
            guard case .failure(let error) = result, let second else {
                if case .success = result {
                    AppLog.player(String(
                        format: "delivery %@ ready in %.0f ms", first.label, elapsed
                    ))
                }
                completion(result)
                return
            }
            // Not every video is served over SABR — some answer with policy and
            // no media on every format, while their legacy URLs serve fine — so
            // a refusal has to fall through rather than fail playback.
            // A throttled identity is the common case here: the range path
            // probes for it and bails, and SABR ignores that quota entirely —
            // so this is the line that shows SABR earning its keep.
            AppLog.player(
                "delivery \(first.label) failed (\(error.localizedDescription)),"
                    + " falling back to \(second.label)"
            )
            PlaybackProgress.step(
                second.label == "sabr"
                    ? "player.status.switchingToSABR"
                    : "player.status.switchingToRanges"
            )
            self?.delivery = second
            second.prepare(request, completion: completion)
        }
    }
}
