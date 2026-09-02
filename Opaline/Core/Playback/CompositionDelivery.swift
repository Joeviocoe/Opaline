import AVFoundation
import Foundation

/// Plays a video/audio pair as an `AVMutableComposition` of two separate
/// assets, with no HLS playlist anywhere in the path.
///
/// This exists because the generated-HLS delivery cannot work below iOS 10:
/// `HLSGenerator` emits `#EXT-X-VERSION:7` with `#EXT-X-MAP`, i.e. fMP4 in HLS,
/// and iOS 9's AVFoundation refuses it. Measured on an iPad 3: the byte-range
/// step resolves in 737 ms, serves both playlists, then fails with
/// AVFoundationErrorDomain -11800 / NSOSStatusErrorDomain -16044.
///
/// `AVMutableComposition` over two `AVURLAsset`s is iOS 7-era API and is how
/// YTNine plays the same streams on the same hardware.
final class CompositionDelivery: StreamDelivery {
    let label = "composition"

    private let client: PlaybackClient

    init(client: PlaybackClient) {
        self.client = client
    }

    func prepare(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let info = request.info
        let headers = client.streamHeaders(visitorData: info.visitorData)
        let videoURL = client.directURL(baseURL: request.video.url, poToken: nil)
        let audioURL = client.directURL(baseURL: request.audio.url, poToken: nil)

        AppLog.player(
            "composition: video itag \(request.video.itag)"
                + " \(request.video.qualityLabel ?? "?")"
                + " \(request.video.codecs), audio itag \(request.audio.itag)"
        )

        // Both streams are served from a loopback HTTP server rather than a
        // resource loader on a custom scheme. AVMutableComposition refuses to
        // compose a resource-loader-backed asset: measured on the device, the
        // tracks load and then insertTimeRange fails with -11801 / -12786 even
        // with the whole stream fetched. An ordinary http://127.0.0.1/… URL is
        // a real, randomly addressable asset, which is what composition wants.
        // The server still fetches upstream in bounded chunks, so googlevideo's
        // open-ended-GET cutoff is avoided just as before.
        let id = UUID().uuidString
        guard let videoLocal = LegacyLoopbackServer.shared.publish(
            LegacyLoopbackServer.Stream(
                url: videoURL,
                headers: headers,
                contentLength: request.video.contentLength,
                contentType: "video/mp4"
            ),
            as: "\(id)-v"
        ), let audioLocal = LegacyLoopbackServer.shared.publish(
            LegacyLoopbackServer.Stream(
                url: audioURL,
                headers: headers,
                contentLength: request.audio.contentLength,
                contentType: "audio/mp4"
            ),
            as: "\(id)-a"
        ) else {
            AppLog.player("composition: loopback server unavailable")
            completion(.failure(StreamDeliveryError.noStream))
            return
        }

        Self.build(
            videoURL: videoLocal,
            audioURL: audioLocal,
            videoTrueMs: request.video.approxDurationMs,
            audioTrueMs: request.audio.approxDurationMs
        ) { item in
            guard let item = item else {
                LegacyLoopbackServer.shared.withdraw("\(id)-v")
                LegacyLoopbackServer.shared.withdraw("\(id)-a")
                completion(.failure(StreamDeliveryError.noStream))
                return
            }
            completion(.success(PreparedPlayback(
                item: item,
                resourceLoader: nil,
                captions: info.captionTracks,
                duration: info.duration
            )))
        }
    }

    // MARK: - Composition

    /// Like `AdaptiveCompositionBuilder`, but the inserted range comes from the
    /// server's stated length rather than the asset's own timeline.
    ///
    /// That difference is the whole point. YouTube's adaptive MP4s read back at
    /// **exactly twice** their real length, confirmed on the device by the
    /// offline downloader: a 841.799 s video track reported 1683.598 s, and its
    /// audio 841.862 s against 1683.725 s. Composing on `asset.duration` — which
    /// is what `AdaptiveCompositionBuilder` does — therefore builds a timeline
    /// twice as long as the media, and playback freezes at the halfway point
    /// with the scrubber claiming there is more to come.
    static func build(
        videoURL: URL,
        audioURL: URL,
        videoTrueMs: Int?,
        audioTrueMs: Int?,
        completion: @escaping (AVPlayerItem?) -> Void
    ) {
        let started = CACurrentMediaTime()
        // No headers needed: the loopback server holds them and applies them to
        // its upstream fetches.
        let video = AVURLAsset(url: videoURL)
        let audio = AVURLAsset(url: audioURL)

        load(video: video, audio: audio) { ok in
            let elapsed = CACurrentMediaTime() - started
            guard ok else {
                AppLog.player(String(format: "composition: metadata failed (%.1fs)", elapsed))
                completion(nil)
                return
            }
            let item = compose(
                video: video,
                audio: audio,
                videoTrueMs: videoTrueMs,
                audioTrueMs: audioTrueMs
            )
            if let item = item {
                PlaybackBufferPolicy.configure(item: item)
                AppLog.player(String(format: "composition: ready (%.1fs)", elapsed))
            }
            completion(item)
        }
    }

    private static func load(
        video: AVURLAsset,
        audio: AVURLAsset,
        completion: @escaping (Bool) -> Void
    ) {
        let group = DispatchGroup()
        var ok = true
        for (asset, label) in [(video, "video"), (audio, "audio")] {
            group.enter()
            // "tracks" ONLY. Asking for "duration" as well makes AVFoundation
            // scan the entire fragmented MP4 to compute an exact length --
            // measured on the device as 48 s to first frame, which is ~91 MB of
            // video and audio pulled before playback could start. The asset's
            // own duration is the number this code deliberately distrusts
            // anyway: it reads back at exactly 2x, which is what
            // `approxDurationMs` is threaded through to correct.
            asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
                var error: NSError?
                if asset.statusOfValue(forKey: "tracks", error: &error) != .loaded {
                    AppLog.player(
                        "composition: \(label) tracks failed: "
                            + "\(error?.localizedDescription ?? "unknown")"
                    )
                    ok = false
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(ok) }
    }

    private static func compose(
        video: AVURLAsset,
        audio: AVURLAsset,
        videoTrueMs: Int?,
        audioTrueMs: Int?
    ) -> AVPlayerItem? {
        guard let sourceVideo = video.tracks(withMediaType: .video).first,
              let sourceAudio = audio.tracks(withMediaType: .audio).first
        else {
            AppLog.player("composition: no video/audio tracks")
            return nil
        }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        let videoRange = range(of: sourceVideo, trueMs: videoTrueMs)
        let audioRange = range(of: sourceAudio, trueMs: audioTrueMs)
        AppLog.player(String(
            format: "composition: video %.1fs (file claims %.1fs), audio %.1fs (claims %.1fs)",
            CMTimeGetSeconds(videoRange.duration),
            CMTimeGetSeconds(sourceVideo.timeRange.duration),
            CMTimeGetSeconds(audioRange.duration),
            CMTimeGetSeconds(sourceAudio.timeRange.duration)
        ))

        do {
            try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
            try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: .zero)
            videoTrack.preferredTransform = sourceVideo.preferredTransform
        } catch {
            AppLog.player("composition: insert failed: \(error)")
            return nil
        }
        return AVPlayerItem(asset: composition)
    }

    /// Clamped to what the track actually offers: a stated length longer than
    /// the media makes the insert fail outright. Same shape as the downloader's
    /// `VideoDownloader+Mux.range(of:trueMs:)`, which this was validated against.
    private static func range(of track: AVAssetTrack, trueMs: Int?) -> CMTimeRange {
        guard let trueMs = trueMs, trueMs > 0 else {
            return track.timeRange
        }
        let stated = CMTime(value: CMTimeValue(trueMs), timescale: 1_000)
        let capped = CMTimeMinimum(stated, track.timeRange.duration)
        return CMTimeRange(start: track.timeRange.start, duration: capped)
    }
}

/// Separate video and audio assets joined with `AVMutableComposition`.
///
/// Declared beside the delivery rather than in `StreamDeliveryFactory` so the
/// legacy port adds nothing to a shared file.
struct CompositionDeliveryFactory: StreamDeliveryFactory {
    let label = "composition"

    /// Needs real URLs to hand AVFoundation, exactly like byte-range delivery;
    /// a SABR-only response carries none.
    func canServe(_ info: DirectPlaybackInfo) -> Bool {
        info.dashVideoFormat?.hasDirectURL ?? false
    }

    func make(
        client: PlaybackClient,
        transport: HTTPTransport,
        poToken: Data?
    ) -> StreamDelivery {
        CompositionDelivery(client: client)
    }
}
