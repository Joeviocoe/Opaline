import Foundation

/// Builds the delivery a source streams through.
///
/// A source no longer picks between byte ranges and SABR — it is handed one.
/// Which one plays is a step in the user's chain, so the choice is visible in
/// settings rather than buried in a heuristic.
protocol StreamDeliveryFactory {
    /// Short name for logs and the stats overlay, e.g. `range`.
    var label: String { get }

    /// Whether this delivery can serve the response at hand. A response whose
    /// formats carry no `url` cannot be fetched by range; one without a SABR
    /// stream cannot be fetched by SABR.
    func canServe(_ info: DirectPlaybackInfo) -> Bool

    func make(
        client: PlaybackClient,
        transport: HTTPTransport,
        poToken: Data?
    ) -> StreamDelivery
}

/// Byte ranges over the `adaptiveFormats` URLs.
struct ByteRangeDeliveryFactory: StreamDeliveryFactory {
    let label = "range"

    func canServe(_ info: DirectPlaybackInfo) -> Bool {
        info.dashVideoFormat?.hasDirectURL ?? false
    }

    func make(
        client: PlaybackClient,
        transport: HTTPTransport,
        poToken: Data?
    ) -> StreamDelivery {
        LegacyRangeDelivery(client: client)
    }
}

/// One `VideoPlaybackAbrRequest` per segment, over the SABR stream URL.
struct SABRDeliveryFactory: StreamDeliveryFactory {
    let label = "sabr"

    func canServe(_ info: DirectPlaybackInfo) -> Bool {
        let verdict = SABRDelivery.canServe(info)
        #if LEGACY_IOS9
        // Whether the server offered SABR at all. Without this a failed SABR
        // test cannot distinguish a broken sink from a video the server never
        // offered SABR for -- and upstream logs this only when parsing fails.
        AppLog.player(
            "sabr offer: url=\(info.serverAbrStreamingURL != nil)"
                + " cfg=\(info.videoPlaybackUstreamerConfig != nil)"
                + " -> canServe=\(verdict)"
        )
        #endif
        return verdict
    }

    func make(
        client: PlaybackClient,
        transport: HTTPTransport,
        poToken: Data?
    ) -> StreamDelivery {
        SABRDelivery(transport: transport, client: client, poToken: poToken)
    }
}
