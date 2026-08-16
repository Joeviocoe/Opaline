import Foundation

/// Default abstract-factory implementation: creates the concrete `VideoSource`
/// for a kind, injecting the shared Innertube `WatchService` into the ones that
/// need it.
struct DefaultVideoSourceFactory: VideoSourceFactory {
    let apiClient: WatchService
    /// SABR media rides the undecorated transport: these requests are anonymous
    /// (an auth header on googlevideo would be wrong) and logging a 1.5MB
    /// response per segment batch is noise.
    var transport: HTTPTransport = ServiceContainer.mediaTransport

    func make(kind: VideoSourceKind) -> VideoSource {
        switch kind {
        case .auto:
            return AutoVideoSource(
                primary: AndroidVRSource(apiClient: apiClient, transport: transport)
            ) { [apiClient] in
                MWebSource(apiClient: apiClient)
            }
        case .androidVR:
            return AndroidVRSource(apiClient: apiClient, transport: transport)
        case .tv:
            return AndroidVRSource(
                apiClient: apiClient, transport: transport, client: .tv, kind: .tv
            )
        case .progressive:
            return ProgressiveSource(apiClient: apiClient)
        case .mwebPot:
            return MWebSource(apiClient: apiClient)
        }
    }
}
