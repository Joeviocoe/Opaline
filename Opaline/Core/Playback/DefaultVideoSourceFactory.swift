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
            return AutoVideoSource(primary: visionOS()) { [self] in
                // Signed in, the fallback is TV: it lists dubs and serves kids
                // content, which the anonymous client does not. Anonymously it
                // is not an option — TVHTML5 answers LOGIN_REQUIRED without a
                // session — so there is nothing below visionOS to fall to, and
                // android_vr stands in only to fail visibly rather than
                // pretending a dead source is a fallback.
                guard OAuthClient.shared.isSignedIn else {
                    return AndroidVRSource(apiClient: apiClient, transport: transport)
                }
                return tv()
            }
        case .visionOS:
            return visionOS()
        case .androidVR:
            return AndroidVRSource(apiClient: apiClient, transport: transport)
        case .tv:
            return tv()
        case .progressive:
            return ProgressiveSource(apiClient: apiClient)
        case .mwebPot:
            return MWebSource(apiClient: apiClient)
        }
    }

    private func visionOS() -> VideoSource {
        AndroidVRSource(
            apiClient: apiClient,
            transport: transport,
            client: .visionOS,
            kind: .visionOS
        )
    }

    private func tv() -> VideoSource {
        AndroidVRSource(
            apiClient: apiClient,
            transport: transport,
            client: .tv,
            kind: .tv
        )
    }
}
