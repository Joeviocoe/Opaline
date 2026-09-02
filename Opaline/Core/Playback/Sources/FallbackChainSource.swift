import Foundation

/// Plays a video by walking the user's chain of steps: the first step that
/// loads wins, and a failure moves to the next one.
///
/// Quality and audio-track questions are delegated to whichever step is
/// playing, so the player shell keeps talking to a single `VideoSource` and
/// never learns that there is a chain at all.
final class FallbackChainSource: VideoSource {
    private static let exhaustedError = NSError(
        domain: "FallbackChainSource",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "No playback source could serve this video"]
    )

    private let steps: [PlaybackStep]
    private let apiClient: WatchService
    /// Sources already built, by step id — a step is built once per video and
    /// reused if the chain comes back to it.
    private var built: [String: VideoSource] = [:]
    /// The step answering playback and quality questions right now.
    private(set) var active: VideoSource?
    private(set) var activeIndex = 0

    var name: String { active?.name ?? steps.first?.id ?? "chain" }
    var listsAudioTracks: Bool { dubCapableSource() != nil }
    var supportsQualitySelection: Bool { active?.supportsQualitySelection ?? false }
    var availableQualities: [VideoQuality] { active?.availableQualities ?? [] }
    var currentQuality: VideoQuality? { active?.currentQuality }
    var currentCodecs: String? { active?.currentCodecs }
    var availableAudioTracks: [AudioTrack] { active?.availableAudioTracks ?? [] }
    var currentAudioTrack: AudioTrack? { active?.currentAudioTrack }

    init(steps: [PlaybackStep], apiClient: WatchService) {
        self.steps = steps
        self.apiClient = apiClient
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        #if LEGACY_IOS9
        LegacyPlaybackTimeline.begin(videoId)
        #endif
        attempt(
            from: 0, videoId: videoId, cancellation: cancellation, completion: completion
        )
    }

    /// Rebuilds on the next step after the current one — what a mid-playback
    /// failure needs, since the step that died will die again.
    func advance(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        attempt(
            from: activeIndex + 1,
            videoId: videoId,
            cancellation: cancellation,
            completion: completion
        )
    }

    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let active = active else {
            completion(.failure(Self.exhaustedError))
            return
        }
        active.selectQuality(quality, resumeAt: resumeAt, completion: completion)
    }

    func selectAudioTrack(
        _ track: AudioTrack,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let active = active else {
            completion(.failure(Self.exhaustedError))
            return
        }
        active.selectAudioTrack(track, resumeAt: resumeAt, completion: completion)
    }

    func probeAudioTracks(
        videoId: String,
        completion: @escaping ([AudioTrack]) -> Void
    ) {
        guard let source = dubCapableSource() else {
            completion([])
            return
        }
        source.probeAudioTracks(videoId: videoId, completion: completion)
    }

    /// Asked of the step that would play, without playing it: the answer is
    /// the ladder the network offers, which is all a downloaded video needs
    /// to show alongside its saved copy.
    func probeQualities(
        videoId: String,
        completion: @escaping ([VideoQuality]) -> Void
    ) {
        guard let step = steps.first else {
            completion([])
            return
        }
        source(for: step).probeQualities(videoId: videoId, completion: completion)
    }

    func releaseResources() {
        built.values.forEach { $0.releaseResources() }
        built.removeAll()
        active = nil
    }

    /// The first step in the chain that can list dubs. Asked by capability,
    /// not by sign-in: visionOS lists and plays them anonymously, so an
    /// account is no longer what dubbed audio depends on.
    func dubCapableSource() -> VideoSource? {
        for step in steps {
            let candidate = source(for: step)
            if candidate.listsAudioTracks {
                return candidate
            }
        }
        return nil
    }

    private func attempt(
        from index: Int,
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard index < steps.count else {
            completion(.failure(Self.exhaustedError))
            return
        }
        guard cancellation?.isCancelled != true else {
            return
        }
        let step = steps[index]
        let source = source(for: step)
        active = source
        activeIndex = index
        if index > 0 {
            PlaybackProgress.step("player.status.tryingFallback")
        }
        source.loadPlayback(videoId: videoId, cancellation: cancellation) { [weak self] result in
            self?.stepFinished(
                result,
                step: step,
                index: index,
                videoId: videoId,
                cancellation: cancellation,
                completion: completion
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func stepFinished(
        _ result: Result<PreparedPlayback, Error>,
        step: PlaybackStep,
        index: Int,
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard case .failure(let error) = result else {
            completion(result)
            return
        }
        AppLog.player("chain: \(step.id) failed (\(error.localizedDescription))")
        DispatchQueue.main.async { [weak self] in
            self?.attempt(
                from: index + 1,
                videoId: videoId,
                cancellation: cancellation,
                completion: completion
            )
        }
    }

    private func source(for step: PlaybackStep) -> VideoSource {
        if let existing = built[step.id] {
            return existing
        }
        let source = step.make(apiClient)
        built[step.id] = source
        return source
    }
}
