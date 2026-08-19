import Foundation

// MARK: - Subtitles saved with the video

extension DownloadStore {
    private static let tracksFileName = "captions.json"

    static func saveCaptionTracks(
        _ tracks: [SubtitleTrack],
        for videoId: String
    ) {
        guard let data = try? JSONEncoder().encode(tracks) else {
            return
        }
        try? data.write(
            to: folder(for: videoId)
                .appendingPathComponent(tracksFileName),
            options: .atomic
        )
    }

    static func captionTracks(for videoId: String) -> [SubtitleTrack]? {
        guard let data = try? Data(contentsOf: folder(for: videoId)
            .appendingPathComponent(tracksFileName)),
            let tracks = try? JSONDecoder().decode(
                [SubtitleTrack].self, from: data
            ) else {
            return nil
        }
        return tracks
    }

    /// Cues are keyed by language rather than by URL: a timedtext URL is
    /// signed and expires, so the one saved yesterday is not the one the
    /// player asks for today.
    static func saveCues(
        _ cues: [SubtitleCue],
        language: String,
        for videoId: String
    ) {
        guard let data = try? JSONEncoder().encode(cues) else {
            return
        }
        try? data.write(
            to: cuesFile(videoId: videoId, language: language),
            options: .atomic
        )
    }

    static func cues(language: String, for videoId: String) -> [SubtitleCue]? {
        guard let data = try? Data(
            contentsOf: cuesFile(videoId: videoId, language: language)
        ) else {
            return nil
        }
        return try? JSONDecoder().decode([SubtitleCue].self, from: data)
    }

    private static func cuesFile(videoId: String, language: String) -> URL {
        let safe = language.replacingOccurrences(of: "/", with: "-")
        return folder(for: videoId)
            .appendingPathComponent("cues-\(safe).json")
    }
}
