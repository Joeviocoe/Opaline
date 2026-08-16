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
        buildGeneratedHLS(
            info: info,
            video: video,
            audio: audio,
            resumeAt: resumeAt,
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
