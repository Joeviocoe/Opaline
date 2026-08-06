import Foundation

// MARK: - Audio-track (dub) selection

extension MWebSource {
    func selectAudioTrack(
        _ track: AudioTrack,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        // Probe-only state (IOS-client metadata, no mweb /player yet): run
        // the full load path; `pendingAudioTrackId` makes the first build
        // start directly on the picked track — no double rebuild.
        guard let info else {
            guard let videoId = currentVideoId else {
                completion(.failure(Self.noStreamError))
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
            completion(.failure(Self.noStreamError))
            return
        }
        setAudioTrackState(
            available: availableAudioTracks, current: track, format: audio
        )
        // Probe path never minted a pot; without one every range 403s (rqh=1).
        if poToken == nil, let videoId = currentVideoId {
            mintPot(videoId: videoId)
        }
        solveThenBuild(info: info, video: video, audio: audio, completion: completion)
    }

    /// Publishes track state from a mweb /player response; consumes any
    /// pending probe-picked track so the first build starts on it.
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
        // A probe-picked track wins; otherwise the auto-dub preference gets
        // to pick the starting track so the first build is already dubbed.
        let pendingId = pendingAudioTrackId
        pendingAudioTrackId = nil
        let startId = pendingId
            ?? AutoDubPreference.autoDubTrack(in: tracks)?.id
        let format = startId.flatMap { id in
            info.allDashAudioFormats.first { $0.audioTrackId == id }
        } ?? info.dashAudioFormat
        if let startId, format?.audioTrackId != startId {
            AppLog.player(
                "mwebSource: start track \(startId) not in mweb formats"
            )
        }
        let current = tracks.first { $0.id == format?.audioTrackId }
            ?? tracks.first { $0.isOriginal }
        setAudioTrackState(available: tracks, current: current, format: format)
        if !tracks.isEmpty {
            let ids = tracks.map(\.id).joined(separator: ",")
            AppLog.player("mwebSource: \(tracks.count) audio tracks [\(ids)]")
        }
    }

    /// IOS-probe results: menu metadata only, no playable formats yet. The
    /// ORIGINAL track shows as current — that's what the playing source
    /// (android_vr) always serves; `isDefault` follows the probe's `hl` and
    /// would tick the AI dub on any video uploaded in another language.
    func applyProbedTracks(_ infos: [AudioTrackInfo]) {
        let tracks = infos.map {
            AudioTrack(
                id: $0.id, displayName: $0.displayName, isDefault: $0.isDefault
            )
        }
        setAudioTrackState(
            available: tracks,
            current: tracks.first { $0.isOriginal }
                ?? tracks.first { $0.isDefault },
            format: nil
        )
    }

    /// The video format matching the active quality (falls back to the
    /// default pick) — audio-track switches keep the current quality.
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
