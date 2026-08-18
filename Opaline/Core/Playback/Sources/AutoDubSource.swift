import Foundation

/// Starts a video on the user's preferred dub when one exists.
///
/// A decorator, not a source: it wraps whatever is playing and races a
/// metadata-only probe against that load. Whoever finishes first decides how
/// the dub starts — probe first and the load commits to the dubbed track,
/// playback first and the shell performs a visible switch. Sources that never
/// list dubs are unaffected, and the wrapped source never learns any of this
/// happened.
final class AutoDubSource: VideoSource {
    private let wrapped: VideoSource
    /// Where dubs can be listed — the signed-in step, when there is one.
    private let dubSource: () -> VideoSource?
    /// The probe's source, kept so a later switch builds on the `/player` it
    /// already fetched instead of fetching it twice.
    private var prober: VideoSource?
    /// Whether the start has been committed to a source already — set by
    /// whichever of the probe and its deadline gets there first.
    private var decided = false
    private var active: VideoSource?

    var name: String { (active ?? wrapped).name }
    var listsAudioTracks: Bool { (active ?? wrapped).listsAudioTracks }
    var supportsQualitySelection: Bool { (active ?? wrapped).supportsQualitySelection }
    var availableQualities: [VideoQuality] { (active ?? wrapped).availableQualities }
    var currentQuality: VideoQuality? { (active ?? wrapped).currentQuality }
    var currentCodecs: String? { (active ?? wrapped).currentCodecs }

    /// The playing source's tracks, or the probed ones while a source that
    /// lists none is playing.
    var availableAudioTracks: [AudioTrack] {
        let tracks = (active ?? wrapped).availableAudioTracks
        return tracks.isEmpty ? (prober?.availableAudioTracks ?? []) : tracks
    }

    var currentAudioTrack: AudioTrack? {
        (active ?? wrapped).currentAudioTrack ?? prober?.currentAudioTrack
    }

    init(wrapping source: VideoSource, dubSource: @escaping () -> VideoSource?) {
        wrapped = source
        self.dubSource = dubSource
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        active = wrapped
        decided = false
        // Without the preference on, or with nowhere to play a dub, there is
        // nothing to decide: play, and let the probe fill the menu behind it.
        guard AutoDubPreference.isEnabled, let dub = dubSource() else {
            loadWrapped(videoId: videoId, cancellation: cancellation, completion: completion)
            probeForMenu(videoId: videoId, cancellation: cancellation)
            return
        }
        prober = dub
        // The probe decides which source starts, so it goes first — it is the
        // cheap IOS listing (~150 ms), not a second /player. A probe that
        // hangs must not hold playback, hence the deadline.
        dub.probeAudioTracks(videoId: videoId) { [weak self] tracks in
            DispatchQueue.main.async {
                self?.probeLanded(
                    tracks,
                    videoId: videoId,
                    cancellation: cancellation,
                    completion: completion
                )
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeDeadline) { [weak self] in
            guard let self, !self.decided, cancellation?.isCancelled != true else {
                return
            }
            AppLog.player("autodub: probe too slow, playing without it")
            self.decided = true
            self.loadWrapped(
                videoId: videoId, cancellation: cancellation, completion: completion
            )
        }
    }

    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        (active ?? wrapped).selectQuality(quality, resumeAt: resumeAt, completion: completion)
    }

    /// Delegates when the playing source owns the track; otherwise rebuilds on
    /// the probed one and promotes it — only on success, so a failed switch
    /// leaves playback untouched.
    func selectAudioTrack(
        _ track: AudioTrack,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let playing = active ?? wrapped
        if playing.availableAudioTracks.contains(track) {
            playing.selectAudioTrack(track, resumeAt: resumeAt, completion: completion)
            return
        }
        guard let prober, prober.availableAudioTracks.contains(track) else {
            completion(.failure(Self.noTrackError))
            return
        }
        AppLog.player("autodub: switching to \(prober.name) for track \(track.id)")
        prober.selectAudioTrack(track, resumeAt: resumeAt) { [weak self] result in
            if case .success = result {
                playing.releaseResources()
                self?.active = prober
            }
            completion(result)
        }
    }

    func probeAudioTracks(
        videoId: String,
        completion: @escaping ([AudioTrack]) -> Void
    ) {
        wrapped.probeAudioTracks(videoId: videoId, completion: completion)
    }

    func releaseResources() {
        wrapped.releaseResources()
        prober?.releaseResources()
        prober = nil
        active = nil
    }
}

// MARK: - Deciding what starts

private extension AutoDubSource {
    /// How long playback waits on the dub probe before going without it.
    static let probeDeadline: TimeInterval = 2

    static let noTrackError = NSError(
        domain: "AutoDubSource",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Audio track unavailable"]
    )

    /// The probe answered in time: start on the wanted dub if there is one,
    /// and otherwise play the chain as usual.
    func probeLanded(
        _ tracks: [AudioTrack],
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard !decided, cancellation?.isCancelled != true else {
            return
        }
        decided = true
        AppLog.player("autodub: probe found \(tracks.count) audio tracks")
        guard let target = AutoDubPreference.autoDubTrack(in: tracks),
              let prober else {
            loadWrapped(videoId: videoId, cancellation: cancellation, completion: completion)
            return
        }
        AppLog.player("autodub: starting on \(prober.name) dub \(target.id)")
        prober.selectAudioTrack(target) { [weak self] result in
            DispatchQueue.main.async {
                self?.dubStarted(
                    result,
                    videoId: videoId,
                    cancellation: cancellation,
                    completion: completion
                )
            }
        }
    }

    /// A dub that will not start is not worth failing playback over — fall
    /// back to the chain and let the video play in its original audio.
    func dubStarted(
        _ result: Result<PreparedPlayback, Error>,
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard case .failure(let error) = result else {
            active = prober
            completion(result)
            return
        }
        AppLog.player("autodub: dub start failed (\(error)), playing original")
        loadWrapped(videoId: videoId, cancellation: cancellation, completion: completion)
    }

    func loadWrapped(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        active = wrapped
        wrapped.loadPlayback(
            videoId: videoId, cancellation: cancellation, completion: completion
        )
    }

    /// Fills the audio-track menu behind playback that has already started.
    /// Nothing depends on the answer, so it never blocks anything.
    func probeForMenu(videoId: String, cancellation: CancellationToken?) {
        guard let source = dubSource() else {
            return
        }
        prober = source
        source.probeAudioTracks(videoId: videoId) { tracks in
            guard !tracks.isEmpty, cancellation?.isCancelled != true else {
                return
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .sourceAudioTracksDidChange, object: self
                )
            }
        }
    }
}
