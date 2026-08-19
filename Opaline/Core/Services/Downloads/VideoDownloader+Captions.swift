import Foundation

// MARK: - Saving subtitles

extension VideoDownloader {
    /// Some videos list dozens of community tracks; nobody watches offline in
    /// twenty languages, and each one is a request at download time.
    /// ponytail: fixed cap, revisit only if someone misses a language.
    static let captionTracksToSave = 10

    /// Matched on the language part alone, so a chosen `pt` takes `pt-BR`.
    /// A video without any of the chosen languages saves nothing rather than
    /// something nobody asked for.
    private static func tracks(
        from tracks: [SubtitleTrack],
        languages: Set<String>
    ) -> [SubtitleTrack] {
        let wanted = Set(languages.map(base))
        return tracks.filter { wanted.contains(base($0.languageCode)) }
    }

    private static func base(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init) ?? code
    }

    /// Parsed cues rather than the raw VTT: the parse is the expensive half
    /// and it would otherwise be redone on every offline play.
    private static func saveCues(of track: SubtitleTrack, videoId: String) {
        SubtitleService.shared.load(track: track) { cues in
            guard !cues.isEmpty else {
                return
            }
            DownloadStore.saveCues(
                cues, language: track.languageCode, for: videoId
            )
        }
    }

    func fetchCaptions(for videoId: String) {
        let wantedLanguages = DownloadPreferences.captionLanguages
        guard !wantedLanguages.isEmpty else {
            return
        }
        apiClient.fetchCaptionTracks(videoId: videoId) { tracks in
            let picked = Self.tracks(from: tracks, languages: wantedLanguages)
            guard !picked.isEmpty else {
                return
            }
            let wanted = Array(picked.prefix(Self.captionTracksToSave))
            DownloadStore.saveCaptionTracks(wanted, for: videoId)
            AppLog.downloads(
                "saving \(wanted.count) caption tracks for \(videoId)"
            )
            wanted.forEach { Self.saveCues(of: $0, videoId: videoId) }
        }
    }
}
