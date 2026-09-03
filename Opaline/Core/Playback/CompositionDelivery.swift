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

    /// The attempt currently running: which streams it published, what it is
    /// for, and who is waiting on it.
    private struct Attempt {
        let key: String
        let ids: [String]
        var waiters: [(Result<PreparedPlayback, Error>) -> Void]
    }

    private var attempt: Attempt?
    private let lock = NSLock()
    #if LEGACY_IOS9
    /// What to run once index priming has finished. Set before priming starts.
    private static var afterPriming: () -> Void = {}
    #endif

    init(client: PlaybackClient) {
        self.client = client
    }

    func prepare(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        // Identity of the work, not of the tap. Two taps on the same video ask
        // for exactly the same bytes.
        let key = request.video.url.absoluteString + "|" + request.audio.url.absoluteString

        lock.lock()
        if var running = attempt, running.key == key {
            // Same video, already loading. Attach to it rather than starting
            // again: a touchscreen double-tap, or a tap repeated because the UI
            // had not updated yet, must not throw away a composition that is
            // already part-loaded. Restarting here is what produced four
            // overlapping attempts, eight competing connections, and an
            // identity throttled to death by googlevideo.
            running.waiters.append(completion)
            attempt = running
            let waiting = running.waiters.count
            lock.unlock()
            AppLog.player("composition: joined the attempt in flight (\(waiting) waiting)")
            return
        }
        let previous = attempt
        lock.unlock()

        // A genuinely different video: stop the old one before starting.
        if let previous = previous {
            AppLog.player("composition: superseding the previous attempt")
            for id in previous.ids {
                LegacyLoopbackServer.shared.withdraw(id)
            }
            for waiter in previous.waiters {
                waiter(.failure(StreamDeliveryError.noStream))
            }
        }

        let info = request.info
        let headers = client.streamHeaders(visitorData: info.visitorData)
        let videoURL = client.directURL(baseURL: request.video.url, poToken: nil)
        let audioURL = client.directURL(baseURL: request.audio.url, poToken: nil)

        AppLog.player(
            "composition: video itag \(request.video.itag)"
                + " \(request.video.qualityLabel ?? "?") \(request.video.codecs)"
                + " \(request.video.contentLength / 1_048_576) MB,"
                + " audio itag \(request.audio.itag)"
                + " \(request.audio.contentLength / 1_048_576) MB"
        )
        // Served from a loopback HTTP server, not a resource loader.
        // AVMutableComposition refuses to compose a resource-loader-backed
        // asset: the tracks load and then insertTimeRange fails with
        // -11801 / -12786 even with the whole stream fetched. An ordinary
        // http://127.0.0.1/… URL is a real, randomly addressable asset.
        let id = UUID().uuidString
        let videoID = "\(id)-v"
        let audioID = "\(id)-a"
        guard let videoLocal = LegacyLoopbackServer.shared.publish(
            LegacyLoopbackServer.Stream(
                url: videoURL,
                headers: headers,
                contentLength: request.video.contentLength,
                contentType: "video/mp4"
            ),
            as: videoID
        ), let audioLocal = LegacyLoopbackServer.shared.publish(
            LegacyLoopbackServer.Stream(
                url: audioURL,
                headers: headers,
                contentLength: request.audio.contentLength,
                contentType: "audio/mp4"
            ),
            as: audioID
        ) else {
            AppLog.player("composition: loopback server unavailable")
            completion(.failure(StreamDeliveryError.noStream))
            return
        }

        lock.lock()
        attempt = Attempt(key: key, ids: [videoID, audioID], waiters: [completion])
        lock.unlock()

        #if LEGACY_IOS9
        // Hand the server the index before anything tries to play.
        //
        // AVFoundation builds its own index by walking every fragment header —
        // measured at ~174 seeks and ~40 s, almost all of it round-trip latency.
        // Those offsets are already known: `sidx` is parsed for the HLS path in
        // 0.4 s and lists all 149 video and 85 audio segments. Fetching their
        // headers up front, in parallel, makes the walk hit memory instead of
        // the network — and pulls about 1 MB where the walk pulled 48 MB.
        //
        // The plain-playback probe that used to run here is retired: it answered
        // its question (plain playback stalls too, so composition was never the
        // sole cause) and every run since cost a flat 20 s timeout that
        // composition waited on — most of the 33.7 s measured on the device.
        Self.afterPriming = {
            Self.startBuild(
                videoLocal: videoLocal,
                audioLocal: audioLocal,
                videoID: videoID,
                audioID: audioID,
                request: request,
                info: info,
                key: key,
                owner: self,
                completion: completion
            )
        }
        // Off the main thread: priming blocks on its fetches, and `prepare` can
        // be called from the main queue. The watchdog would have caught it, but
        // a frozen UI during "Resolving stream…" is exactly the symptom being
        // fixed here.
        DispatchQueue.global(qos: .userInitiated).async {
            Self.primeIndex(
                videoID: videoID,
                audioID: audioID,
                video: request.video,
                audio: request.audio,
                headers: headers,
                videoURL: videoURL,
                audioURL: audioURL
            )
            DispatchQueue.main.async {
                Self.afterPriming()
            }
        }

        #else
        Self.startBuild(
            videoLocal: videoLocal,
            audioLocal: audioLocal,
            videoID: videoID,
            audioID: audioID,
            request: request,
            info: info,
            key: key,
            owner: self,
            completion: completion
        )
        #endif
    }

    // swiftlint:disable:next function_parameter_count
    private static func startBuild(
        videoLocal: URL,
        audioLocal: URL,
        videoID: String,
        audioID: String,
        request: DeliveryRequest,
        info: DirectPlaybackInfo,
        key: String,
        owner: CompositionDelivery?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        build(
            videoURL: videoLocal,
            audioURL: audioLocal,
            videoID: videoID,
            audioID: audioID,
            videoTrueMs: request.video.approxDurationMs,
            audioTrueMs: request.audio.approxDurationMs
        ) { [weak owner] item in
            guard let self = owner else { return }
            self.lock.lock()
            let mine = self.attempt?.key == key
            let waiters = mine ? (self.attempt?.waiters ?? []) : []
            if mine { self.attempt = nil }
            self.lock.unlock()
            guard mine else {
                // Superseded while loading; its streams are already withdrawn.
                return
            }

            let result: Result<PreparedPlayback, Error>
            if let item = item {
                result = .success(PreparedPlayback(
                    item: item,
                    resourceLoader: nil,
                    captions: info.captionTracks,
                    duration: info.duration
                ))
            } else {
                LegacyLoopbackServer.shared.withdraw(videoID)
                LegacyLoopbackServer.shared.withdraw(audioID)
                result = .failure(StreamDeliveryError.noStream)
            }
            for waiter in waiters {
                waiter(result)
            }
        }
    }

    // MARK: - Index priming

    #if LEGACY_IOS9
    /// Fetches each stream's `sidx` and primes the server with the head of
    /// every segment.
    ///
    /// Best-effort throughout: a stream whose index cannot be read simply falls
    /// back to AVFoundation doing the walking, which is slow but correct.
    private static func primeIndex(
        videoID: String,
        audioID: String,
        video: DashFormatInfo,
        audio: DashFormatInfo,
        headers: [String: String],
        videoURL: URL,
        audioURL: URL
    ) {
        AppLog.player(
            "prime: start — video index \(video.indexRangeStart)-\(video.indexRangeEnd),"
                + " audio index \(audio.indexRangeStart)-\(audio.indexRangeEnd)"
        )
        for (id, format, url) in [
            (videoID, video, videoURL), (audioID, audio, audioURL),
        ] {
            guard format.indexRangeEnd > format.indexRangeStart else { continue }
            guard let index = fetchRange(
                url: url,
                headers: headers,
                start: Int64(format.indexRangeStart),
                end: Int64(format.indexRangeEnd)
            ), let segments = HLSGenerator.parseSidx(data: index) else {
                AppLog.player("prime: no sidx for \(id.suffix(2)), falling back to the walk")
                continue
            }
            // Only the head of each segment: the `moof` box, not its media.
            //
            // 16 KB, not 4 KB. A five-second 30 fps fragment carries ~150
            // samples, and a `trun` with per-sample duration, size and flags is
            // ~1.8 KB before box overhead — 4 KB left no margin, and a truncated
            // `trun` parses into a short sample list that looks plausible.
            // 149 fragments x 16 KB is ~2.4 MB, still seconds in parallel.
            let headBytes: Int64 = 16 * 1024
            // `sidx` offsets are relative to the START OF THE MEDIA, not to the
            // file: parseSidxContent accumulates segment sizes from zero. Media
            // begins just past the index box, which is what upstream's HLS
            // generator calls `dataStartOffset`. Without this base every
            // "fragment" fetched was actually the init segment and index region,
            // and all 68 parsed empty.
            let mediaBase = Int64(format.indexRangeEnd) + 1
            let ranges = segments.map { segment -> (Int64, Int64) in
                let start = mediaBase + segment.offset
                return (start, min(start + headBytes - 1, start + segment.size - 1))
            }
            LegacyLoopbackServer.shared.prime(id, ranges: ranges)
            LegacyPlaybackTimeline.mark("index primed (\(id.suffix(2)))")

            // Everything needed for a progressive file is now in hand: the init
            // segment's track config, and every fragment's sample table. Build
            // it, and the player never walks the file at all.
            guard let initData = fetchRange(
                url: url, headers: headers, start: 0, end: Int64(format.initRangeEnd)
            ), let config = LegacyProgressiveRemux.parseInit(initData) else {
                AppLog.player("remux: no init segment for \(id.suffix(2)), serving raw")
                continue
            }
            let fragments = LegacyLoopbackServer.shared.primedData(id)
            var samples: [LegacyProgressiveRemux.Sample] = []
            var parsed = 0
            var emptyFragments = 0
            for segment in segments {
                let origin = mediaBase + segment.offset
                guard let data = fragments[origin] else { continue }
                let batch = LegacyProgressiveRemux.parseFragment(data, moofAt: origin)
                if batch.isEmpty {
                    // A fragment whose header did not fit in the primed 4 KB, or
                    // one this parser does not understand. Either way the
                    // timeline would have a hole, so it is counted and the
                    // validator refuses the whole remux below.
                    emptyFragments += 1
                } else {
                    parsed += 1
                }
                samples += batch
            }
            AppLog.player(
                "remux[\(id.suffix(2))]: \(parsed) fragments parsed,"
                    + " \(emptyFragments) empty, \(segments.count - fragments.count) unfetched"
            )
            guard let remuxed = LegacyProgressiveRemux.build(
                config: config,
                samples: samples,
                label: String(id.suffix(2)),
                expectedDurationMs: format.approxDurationMs,
                originLength: format.contentLength,
                fragmentsSeen: parsed,
                fragmentsExpected: segments.count
            ) else {
                continue
            }
            LegacyLoopbackServer.shared.attachRemux(remuxed, to: id)
            LegacyPlaybackTimeline.mark("remuxed to progressive (\(id.suffix(2)))")
        }
    }

    /// One blocking ranged GET. Only ever called off the main thread, from the
    /// delivery's own work.
    private static func fetchRange(
        url: URL,
        headers: [String: String],
        start: Int64,
        end: Int64
    ) -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) {
                result = data
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return result
    }
    #endif

    // MARK: - Composition

    /// Like `AdaptiveCompositionBuilder`, but the inserted range comes from the
    /// server's stated length rather than the asset's own timeline.
    ///
    /// That difference is the whole point. YouTube's adaptive MP4s read back at
    /// **exactly twice** their real length, confirmed on the device by the
    /// offline downloader: a 841.799 s video track reported 1683.598 s.
    /// Composing on `asset.duration` therefore builds a timeline twice as long
    /// as the media, and playback freezes at the halfway point with the
    /// scrubber claiming there is more to come.
    static func build(
        videoURL: URL,
        audioURL: URL,
        videoID: String,
        audioID: String,
        videoTrueMs: Int?,
        audioTrueMs: Int?,
        completion: @escaping (AVPlayerItem?) -> Void
    ) {
        let started = CACurrentMediaTime()
        func elapsed() -> String {
            String(format: "%.1fs", CACurrentMediaTime() - started)
        }
        func served() -> String {
            let video = LegacyLoopbackServer.shared.bytesServed(videoID) / 1024
            let audio = LegacyLoopbackServer.shared.bytesServed(audioID) / 1024
            return "\(video) KB video + \(audio) KB audio"
        }

        // Precise duration and timing is left ON, deliberately.
        //
        // Turning it off was an attempt to stop AVFoundation scanning the whole
        // fragmented MP4. It did not: reads stayed at ~37 MB. What it did do was
        // leave the video track with no usable frame timing — logged as
        // `0 fps`, and on screen as audio playing over a black picture while the
        // audio track, being simpler, survived. Not worth it for a saving that
        // never materialised.
        let video = AVURLAsset(url: videoURL)
        let audio = AVURLAsset(url: audioURL)

        load(video: video, audio: audio) { ok in
            AppLog.player("composition: tracks loaded at \(elapsed()), read \(served())")
            LegacyPlaybackTimeline.mark("asset tracks loaded", detail: served())
            guard ok else {
                AppLog.player("composition: metadata failed at \(elapsed())")
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
                AppLog.player("composition: ready at \(elapsed()), read \(served())")
                LegacyPlaybackTimeline.mark("composition built", detail: served())
            } else {
                AppLog.player("composition: compose failed at \(elapsed()), read \(served())")
            }
            // Back to main only to hand over the finished item: everything
            // downstream touches the player and the view hierarchy.
            DispatchQueue.main.async { completion(item) }
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
            // "tracks" ONLY. Adding "duration" makes AVFoundation scan the
            // entire fragmented MP4 to compute an exact length.
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
        // NOT the main queue. The caller composes inside this completion, and
        // `insertTimeRange` over 44,000 samples takes over a second on an A5X —
        // measured as a 1183 ms / 1517 ms main-thread stall landing exactly when
        // the player became ready, with 70-90 frames dropped. Composition is not
        // UIKit work and has no business on the main thread.
        group.notify(queue: .global(qos: .userInitiated)) { completion(ok) }
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
            format: "composition: video %.1fs (file claims %.1fs) %@ %.0f fps,"
                + " audio %.1fs (claims %.1fs)",
            CMTimeGetSeconds(videoRange.duration),
            CMTimeGetSeconds(sourceVideo.timeRange.duration),
            "\(Int(sourceVideo.naturalSize.width))x\(Int(sourceVideo.naturalSize.height))",
            Double(sourceVideo.nominalFrameRate),
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
