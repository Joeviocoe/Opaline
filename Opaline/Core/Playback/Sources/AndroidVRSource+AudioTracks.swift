import Foundation

// MARK: - Audio-track (dub) selection
//
// Only the TV client ever lists dubs here: android_vr returns the original
// track alone, so `allDashAudioFormats` stays empty and the picker stays off.
//
// On SABR a track change is a format change — the session re-opens with the
// chosen audio format in `preferred_audio_format_ids`, which is exactly what a
// quality switch does for video, so it goes through the same build path.

extension AndroidVRSource {
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
        let startId = AutoDubPreference.autoDubTrack(in: tracks)?.id
        let format = startId.flatMap { id in
            info.allDashAudioFormats.first { $0.audioTrackId == id }
        } ?? info.dashAudioFormat
        let current = tracks.first { $0.id == format?.audioTrackId }
            ?? tracks.first { $0.isOriginal }
        (availableAudioTracks, currentAudioTrack, currentAudioFormat)
            = (tracks, current, format)
        if !tracks.isEmpty {
            let ids = tracks.map(\.id).joined(separator: ",")
            AppLog.player("\(kind): \(tracks.count) audio tracks [\(ids)]")
        }
    }

    /// Metadata-only probe: the client's own `/player` response already lists
    /// every dub, so the probe is the fetch a later switch would have to make
    /// anyway — it just stops short of building playback.
    func probeAudioTracks(
        videoId: String,
        completion: @escaping ([AudioTrack]) -> Void
    ) {
        fetchInfo(videoId: videoId, cancellation: nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let info) = result else {
                    completion([])
                    return
                }
                self.apply(info)
                // Another source is playing, and it plays the ORIGINAL track —
                // ticking the auto-dub pick here would show a track that is
                // not what is coming out of the speakers.
                self.currentAudioTrack = self.availableAudioTracks
                    .first { $0.isOriginal }
                completion(self.availableAudioTracks)
            }
        }
    }

    func selectAudioTrack(
        _ track: AudioTrack,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let info,
              let audio = info.allDashAudioFormats.first(
                  where: { $0.audioTrackId == track.id }
              ),
              let video = currentVideoFormat(info: info) else {
            completion(.failure(NSError(
                domain: "AndroidVRSource",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No such audio track"]
            )))
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
