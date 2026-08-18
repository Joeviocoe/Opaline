import Foundation

/// One attempt at playing a video: a client and a delivery.
///
/// Steps are what the user orders and switches off in settings, and what the
/// chain walks in that order. Adding a way to play is adding a step to the
/// registry — nothing else in the app learns its name.
struct PlaybackStep {
    /// Stable identifier, stored in settings. Never change a shipped one.
    let id: String
    /// What the settings screen and the stats overlay call this step.
    let title: String
    /// Steps that need an account skip themselves when there is no session,
    /// which is what keeps "are we signed in?" out of the playback code.
    let requiresSignIn: Bool
    let make: (WatchService) -> VideoSource
}

/// Every way this app knows how to play a video, in the order they are
/// offered by default.
///
/// Composed here rather than switched on anywhere: the registry is the only
/// place that knows which clients and deliveries exist.
struct PlaybackStepRegistry {
    static let `default` = PlaybackStepRegistry(steps: [
        PlaybackStep(
            id: "visionos.range",
            title: "visionOS · byte ranges",
            requiresSignIn: false
        ) { apiClient in
            innertube(
                apiClient: apiClient,
                client: VisionOSClient(),
                delivery: ByteRangeDeliveryFactory(),
                title: "visionos.range"
            )
        },
        PlaybackStep(
            id: "tv.sabr",
            title: "TV · SABR",
            requiresSignIn: true
        ) { apiClient in
            innertube(
                apiClient: apiClient,
                client: TVClient(),
                delivery: SABRDeliveryFactory(),
                title: "tv.sabr"
            )
        },
        PlaybackStep(
            id: "visionos.sabr",
            title: "visionOS · SABR",
            requiresSignIn: false
        ) { apiClient in
            innertube(
                apiClient: apiClient,
                client: VisionOSClient(),
                delivery: SABRDeliveryFactory(),
                title: "visionos.sabr"
            )
        },
        PlaybackStep(
            id: "progressive",
            title: "Progressive 360p",
            requiresSignIn: false
        ) { apiClient in
            ProgressiveSource(apiClient: apiClient)
        }
    ])

    let steps: [PlaybackStep]

    private static func innertube(
        apiClient: WatchService,
        client: PlaybackClient,
        delivery: StreamDeliveryFactory,
        title: String
    ) -> VideoSource {
        InnertubeVideoSource(
            apiClient: apiClient,
            client: client,
            name: title,
            deliveryFactory: delivery
        )
    }

    func step(id: String) -> PlaybackStep? {
        steps.first { $0.id == id }
    }
}
