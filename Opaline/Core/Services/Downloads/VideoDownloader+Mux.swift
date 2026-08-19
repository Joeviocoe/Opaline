import AVFoundation
import Foundation

// MARK: - Remux

extension VideoDownloader {
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
        video: URL,
        audio: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        markMuxing()
        AppLog.downloads(
            "mux \(videoId): video \(Self.fileSize(video)) B,"
                + " audio \(Self.fileSize(audio)) B"
        )
        let composition = AVMutableComposition()
        do {
            try append(url: video, type: .video, to: composition)
            try append(url: audio, type: .audio, to: composition)
        } catch {
            fail(videoId: videoId, error: error, completion: completion)
            return
        }
        export(composition, videoId: videoId, completion: completion)
    }

    /// The track's own `timeRange`, never the asset's `duration`: YouTube's
    /// adaptive MP4s routinely claim a duration in the file header that does
    /// not match what the track actually holds, and inserting the claimed
    /// range yields a file that ends early or plays silence at the tail.
    private func append(
        url: URL,
        type: AVMediaType,
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
        AppLog.downloads(
            "\(type.rawValue) track \(CMTimeGetSeconds(source.timeRange.duration))s"
                + " (file claims \(CMTimeGetSeconds(asset.duration))s)"
        )
        try target.insertTimeRange(
            source.timeRange, of: source, at: .zero
        )
    }

    private func export(
        _ composition: AVMutableComposition,
        videoId: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let output = DownloadStore.videoFile(for: videoId)
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            fail(videoId: videoId, error: DownloadError.export, completion: completion)
            return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.exportAsynchronously { [weak self] in
            guard session.status == .completed else {
                let error = session.error ?? DownloadError.export
                self?.fail(videoId: videoId, error: error, completion: completion)
                return
            }
            self?.finish(videoId: videoId)
            DownloadStore.removeParts(for: videoId)
            DownloadStore.announceChange()
            AppLog.downloads("finished \(videoId)")
            DispatchQueue.main.async { completion(.success(output)) }
        }
    }
}
