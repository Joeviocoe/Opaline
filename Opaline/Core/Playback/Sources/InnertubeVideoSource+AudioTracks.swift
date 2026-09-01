import Foundation

// MARK: - Audio-track (dub) selection
//
// Only the TV client ever lists dubs here: the anonymous clients returns the original
// track alone, so `allDashAudioFormats` stays empty and the picker stays off.
//
// On SABR a track change is a format change — the session re-opens with the
// chosen audio format in `preferred_audio_format_ids`, which is exactly what a
// quality switch does for video, so it goes through the same build path.

extension InnertubeVideoSource {
    static var noTrackError: Error {
        NSError(
            domain: "InnertubeVideoSource",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "No such audio track"]
        )
    }

    /// The audio to build with: the picked dub, else the response's default.
    func audioFormat(in info: DirectPlaybackInfo) -> DashFormatInfo? {
        currentAudioFormat ?? info.dashAudioFormat
    }

    /// Publishes track state from a /player response, starting on the
    /// auto-dub preference's pick when it names one the response carries.
    func updateAudioTrackState(from info: DirectPlaybackInfo) {
        let tracks = info.allDashAudioFormats.compactMap { format in
            format.audioTrackId.map {
                AudioTrack(
                    id: $0,
                    displayName: format.audioTrackName ?? $0,
                    isDefault: format.audioIsDefault
                )
            }
        }
        // A probe-picked track wins; otherwise the auto-dub preference picks,
        // so the very first build is already on the right track.
        let pendingId = pendingAudioTrackId
        pendingAudioTrackId = nil
        let startId = pendingId ?? AutoDubPreference.autoDubTrack(in: tracks)?.id
        let format = startId.flatMap { id in
            info.allDashAudioFormats.first { $0.audioTrackId == id }
        } ?? info.dashAudioFormat
        if let startId = startId, format?.audioTrackId != startId {
            AppLog.player("\(name): start track \(startId) not in formats")
        }
        let current = tracks.first { $0.id == format?.audioTrackId }
            ?? tracks.first { $0.isOriginal }
        (availableAudioTracks, currentAudioTrack, currentAudioFormat)
            = (tracks, current, format)
        if !tracks.isEmpty {
            let ids = tracks.map(\.id).joined(separator: ",")
            AppLog.player("\(name): \(tracks.count) audio tracks [\(ids)]")
        }
    }

    /// Metadata-only probe, and deliberately NOT this source's own `/player`.
    ///
    /// The probe exists to beat the primary load to the answer "does this
    /// video have the dub the user asked for" — and it cannot do that through
    /// the TV client: that path mints a po token first and then parses a
    /// hundred-odd formats, ~780 ms warm, while the anonymous client is playing in 340.
    /// The IOS listing answers the same question logged-out, with no token and
    /// no ladder to parse. Track ids match across the clients.
    func probeAudioTracks(
        videoId: String,
        completion: @escaping ([AudioTrack]) -> Void
    ) {
        currentVideoId = videoId
        apiClient.fetchAudioTrackList(videoId: videoId) { [weak self] infos in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion([])
                    return
                }
                // Only fill in probe state while there is no real response to
                // contradict: the probe races the load and must never clobber
                // formats a `/player` answer already published.
                if self.info == nil {
                    self.applyProbedTracks(infos)
                }
                completion(self.availableAudioTracks)
            }
        }
    }

    /// Probe results: menu metadata only, no playable formats behind them.
    /// The ORIGINAL track shows as current — that is what the source actually
    /// playing (the anonymous client) serves; `isDefault` follows the probe's `hl` and
    /// would tick an AI dub on any video uploaded in another language.
    private func applyProbedTracks(_ infos: [AudioTrackInfo]) {
        let tracks = infos.map {
            AudioTrack(
                id: $0.id, displayName: $0.displayName, isDefault: $0.isDefault
            )
        }
        availableAudioTracks = tracks
        currentAudioTrack = tracks.first { $0.isOriginal }
            ?? tracks.first { $0.isDefault }
        currentAudioFormat = nil
        if !tracks.isEmpty {
            let ids = tracks.map(\.id).joined(separator: ",")
            AppLog.player("\(name) probe: \(tracks.count) audio tracks [\(ids)]")
        }
    }

    func selectAudioTrack(
        _ track: AudioTrack,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        // Probe-only state: no `/player` response yet, so run the full load.
        // `pendingAudioTrackId` makes that first build start on the picked
        // track rather than building the original and rebuilding after.
        guard let info = info else {
            guard let videoId = currentVideoId else {
                completion(.failure(Self.noTrackError))
                return
            }
            pendingAudioTrackId = track.id
            loadPlayback(videoId: videoId, cancellation: nil, completion: completion)
            return
        }
        guard let audio = info.allDashAudioFormats.first(
                  where: { $0.audioTrackId == track.id }
              ),
              let video = currentVideoFormat(info: info) else {
            completion(.failure(Self.noTrackError))
            return
        }
        (currentAudioTrack, currentAudioFormat) = (track, audio)
        // The auto-dub start has no playhead of its own — it is the first
        // build of the video, so it begins where the last one stopped.
        let start = resumeAt ?? currentVideoId.flatMap {
            WatchProgressStore.shared.resumeSeconds(
                forVideoId: $0, duration: info.duration
            )
        }
        buildGeneratedHLS(
            info: info,
            video: video,
            audio: audio,
            resumeAt: start,
            completion: completion
        )
    }

    /// The video format matching the active quality (falls back to the
    /// default pick) — a track switch keeps the current quality.
    private func currentVideoFormat(
        info: DirectPlaybackInfo
    ) -> DashFormatInfo? {
        if let quality = currentQuality,
           let format = info.allDashVideoFormats.first(
               where: { "\($0.itag)" == quality.id }
           ) {
            return format
        }
        return info.dashVideoFormat
    }
}
