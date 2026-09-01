import AVFoundation
import Foundation

// MARK: - Remux

extension VideoDownloader {
    /// Clamped to what the track actually offers: a stated length longer than
    /// the media would make the insert fail outright.
    private static func range(
        of track: AVAssetTrack,
        trueMs: Int?
    ) -> CMTimeRange {
        guard let trueMs = trueMs, trueMs > 0 else {
            return track.timeRange
        }
        let stated = CMTime(value: CMTimeValue(trueMs), timescale: 1_000)
        let capped = CMTimeMinimum(stated, track.timeRange.duration)
        return CMTimeRange(start: track.timeRange.start, duration: capped)
    }

    /// Tells a truncated download apart from a container AVFoundation would
    /// not open — the two fail at the same place otherwise.
    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// Joins the two downloaded tracks into one MP4 without re-encoding.
    ///
    /// Passthrough is the whole point: on an A7 a real export of a
    /// ten-minute 1080p video would run longer than the download did, and
    /// the bytes are already in the codecs the player wants.
    func mux(
        videoId: String,
        option: DownloadOption,
        parts: (video: URL, audio: URL)
    ) {
        let (video, audio) = parts
        markMuxing()
        AppLog.downloads(
            "mux \(videoId): video \(Self.fileSize(video)) B,"
                + " audio \(Self.fileSize(audio)) B"
        )
        let composition = AVMutableComposition()
        do {
            try append(
                url: video,
                type: .video,
                trueMs: option.video.approxDurationMs,
                to: composition
            )
            try append(
                url: audio,
                type: .audio,
                trueMs: option.audio.approxDurationMs,
                to: composition
            )
        } catch {
            fail(videoId: videoId, error: error)
            return
        }
        export(composition, videoId: videoId)
    }

    /// The length the server states, not the one AVFoundation computes.
    ///
    /// Measured 2026-08-19: a byte-exact copy of YouTube's adaptive MP4 reads
    /// back as exactly twice its real length (507.83 s for a 253.92 s track,
    /// on both the video and the audio part). The bytes are right — expected
    /// and written sizes matched to the byte — so the file's own timeline is
    /// what cannot be trusted, and `approxDurationMs` is taken instead.
    private func append(
        url: URL,
        type: AVMediaType,
        trueMs: Int?,
        to composition: AVMutableComposition
    ) throws {
        let asset = AVURLAsset(url: url)
        guard let source = asset.tracks(withMediaType: type).first,
              let target = composition.addMutableTrack(
                  withMediaType: type,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw DownloadError.noTracks
        }
        let range = Self.range(of: source, trueMs: trueMs)
        AppLog.downloads(
            "\(type.rawValue) track \(CMTimeGetSeconds(range.duration))s"
                + " (file claims \(CMTimeGetSeconds(source.timeRange.duration))s)"
        )
        try target.insertTimeRange(range, of: source, at: .zero)
    }

    private func export(
        _ composition: AVMutableComposition,
        videoId: String
    ) {
        let output = DownloadStore.videoFile(for: videoId)
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            fail(videoId: videoId, error: DownloadError.export)
            return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.exportAsynchronously { [weak self] in
            guard session.status == .completed else {
                let error = session.error ?? DownloadError.export
                self?.fail(videoId: videoId, error: error)
                return
            }
            DownloadStore.removeParts(for: videoId)
            AppLog.downloads("finished \(videoId)")
            self?.finishJob(reporting: .success(output))
        }
    }
}
