#if LEGACY_IOS9
import Foundation

/// Serves a SABR session as MPEG-TS instead of fragmented MP4.
///
/// SABR's own sink is fMP4 in HLS, which needs `#EXT-X-VERSION:7` and
/// `#EXT-X-MAP` — both iOS 10. MPEG-TS in HLS has worked since HLS existed, so
/// the container is the only thing that has to change: the same fragments are
/// fetched, then transmuxed on the way out.
///
/// The progressive-remux trick cannot be reused here. That one rewrites an
/// index into a `moov` the player can seek within, which needs byte ranges over
/// the whole file; SABR hands out a sequential stream with no ranges at all.
enum LegacySABRTSRoute {
    static let mimeType = "video/mp2t"

    /// Guards the setup cache. The loopback server answers on its own queue and
    /// two tracks open at once, so this is genuinely concurrent.
    private static let queue = DispatchQueue(label: "com.ytvlite.sabr-ts")
    private static var setups: [String: LegacyTSTransmuxer.TrackSetup] = [:]
    /// Callers waiting on an init fetch already in flight. Without this, video
    /// and audio each fetch their own init twice when the player opens both
    /// playlists at once.
    private static var waiting: [String: [(LegacyTSTransmuxer.TrackSetup?) -> Void]] = [:]

    /// Drops cached setups. A new generation means new formats.
    static func reset() {
        queue.async {
            setups.removeAll()
            waiting.removeAll()
        }
    }

    // MARK: - Playlist

    /// A version 3 media playlist: plain `#EXTINF` segments, no `#EXT-X-MAP`.
    ///
    /// Segment durations come from the same `sidx` the fMP4 playlist uses, so
    /// the timeline is identical — only the container differs.
    static func playlist(for track: SABRDelivery.Track, route: SABRDelivery.Route) -> Data {
        let maxDur = track.segments.map(\.duration).max() ?? 5
        var lines = ["#EXTM3U", "#EXT-X-VERSION:3"]
        lines.append("#EXT-X-TARGETDURATION:\(Int(ceil(maxDur)))")
        lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
        if let startAt = route.startAt, startAt > 0 {
            lines.append(
                String(format: "#EXT-X-START:TIME-OFFSET=%.3f,PRECISE=YES", startAt)
            )
        }
        let base = "/g\(route.generation)/s/\(track.path)"
        for (index, segment) in track.segments.enumerated() {
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append("\(base)/\(index)")
        }
        lines.append("#EXT-X-ENDLIST")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// The master playlist, at a version iOS 9 implements.
    ///
    /// Upstream emits `#EXT-X-VERSION:7` with `#EXT-X-INDEPENDENT-SEGMENTS`, a
    /// version 6 tag. A client must reject a playlist whose version it does not
    /// implement, so the master has to come down to 4 — which is the version
    /// that introduced `EXT-X-MEDIA`, and so the lowest one that can still carry
    /// audio as a separate rendition.
    static func masterPlaylist(route: SABRDelivery.Route) -> String {
        guard route.tracks.count == 2,
              let video = route.tracks.first,
              let audio = route.tracks.last else {
            AppLog.hls("ts: master needs two tracks, have \(route.tracks.count)")
            return ""
        }
        let audioPeak = HLSGenerator.peakBitrate(
            audio.segments, fallback: audio.format.bitrate
        )
        let videoPeak = HLSGenerator.peakBitrate(
            video.segments, fallback: video.format.bitrate
        )
        let width = video.format.width ?? 1_280
        let height = video.format.height ?? 720
        var lines = ["#EXTM3U", "#EXT-X-VERSION:4"]
        lines.append(
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"Main\""
                + ",DEFAULT=YES,AUTOSELECT=YES"
                + ",URI=\"/g\(route.generation)/\(audio.path).m3u8\""
        )
        lines.append(
            "#EXT-X-STREAM-INF:BANDWIDTH=\(videoPeak + audioPeak)"
                + ",CODECS=\"\(video.format.codecs),\(audio.format.codecs)\""
                + ",RESOLUTION=\(width)x\(height)"
                + ",AUDIO=\"audio\""
        )
        lines.append("/g\(route.generation)/\(video.path).m3u8")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Segments

    static func serve(
        _ name: String,
        of track: SABRDelivery.Track,
        route: SABRDelivery.Route,
        completion: @escaping (Data?, String) -> Void
    ) {
        guard let index = Int(name), index < track.segments.count else {
            AppLog.hls("ts: \(track.path)/\(name) is not a segment index")
            completion(nil, "")
            return
        }
        setup(for: track, route: route) { setup in
            guard let setup = setup else {
                completion(nil, "")
                return
            }
            fetch(index: index, of: track, route: route) { data in
                guard let data = data else {
                    completion(nil, "")
                    return
                }
                // A media segment may legally open with styp, sidx or emsg.
                // Both the fragment parser and the transmuxer expect the
                // buffer to start at the moof, so trim rather than teach each
                // of them to scan -- and the composition path, which fetches
                // at an exact moof offset, keeps its stricter assumption.
                guard let fragment = trimmedToMoof(data, track: track, index: index) else {
                    completion(nil, "")
                    return
                }
                let started = Date()
                let ts = LegacyTSTransmuxer.segment(
                    fragment: fragment,
                    moofAt: 0,
                    setup: setup,
                    baseMediaTime: baseDecodeTime(
                        of: fragment, index: index, track: track, setup: setup
                    )
                )
                guard let ts = ts else {
                    AppLog.hls(
                        "ts: \(track.path)/\(index) transmux failed"
                            + " from \(data.count) bytes"
                    )
                    completion(nil, "")
                    return
                }
                let ms = Int(Date().timeIntervalSince(started) * 1_000)
                AppLog.hls(
                    "ts: \(track.path)/\(index) \(data.count) -> \(ts.count) bytes"
                        + " in \(ms)ms"
                )
                completion(ts, mimeType)
            }
        }
    }

    /// Drops any boxes ahead of the `moof`.
    ///
    /// Returns nil rather than passing the buffer through: without a moof there
    /// is nothing to transmux, and the parser's own complaint would name the
    /// leading box instead of the real problem.
    private static func trimmedToMoof(
        _ data: Data,
        track: SABRDelivery.Track,
        index: Int
    ) -> Data? {
        var scan = 0
        while let box = MP4Box.header(in: data, at: scan) {
            if box.type == "moof" {
                guard scan > 0 else { return data }
                return data.subdata(in: (data.startIndex + scan)..<data.endIndex)
            }
            AppLog.hls("ts: \(track.path)/\(index) skipping leading '\(box.type)'")
            guard box.next > scan else { break }
            scan = box.next
        }
        AppLog.hls(
            "ts: \(track.path)/\(index) has no moof in \(data.count) bytes"
        )
        return nil
    }

    /// The fragment's own `tfdt`, falling back to the sidx timeline.
    ///
    /// Timestamps must be continuous across segments or the player treats each
    /// one as a discontinuity and audio drifts. `tfdt` states this exactly;
    /// the sidx sum is a good enough answer when a fragment omits it.
    private static func baseDecodeTime(
        of fragment: Data,
        index: Int,
        track: SABRDelivery.Track,
        setup: LegacyTSTransmuxer.TrackSetup
    ) -> UInt64 {
        let base = fragment.startIndex
        if let tfdt = MP4Box.find("moof/traf/tfdt", in: fragment),
           base + tfdt.payloadStart < fragment.endIndex {
            let version = fragment[base + tfdt.payloadStart]
            let at = tfdt.payloadStart + 4
            if version == 1 {
                if let value = MP4Box.be64(fragment, base + at) { return value }
            } else if let value = MP4Box.be32(fragment, base + at) {
                return UInt64(value)
            }
        }
        let ms = SABRDelivery.startMs(of: index, in: track)
        AppLog.hls("ts: \(track.path)/\(index) has no tfdt, using sidx \(ms)ms")
        return UInt64(ms) * UInt64(setup.timescale) / 1_000
    }

    // MARK: - Track setup

    /// Codec configuration for a track, fetched once and cached.
    private static func setup(
        for track: SABRDelivery.Track,
        route: SABRDelivery.Route,
        completion: @escaping (LegacyTSTransmuxer.TrackSetup?) -> Void
    ) {
        let key = "\(route.generation)/\(track.path)"
        var shouldFetch = false
        var cached: LegacyTSTransmuxer.TrackSetup?
        queue.sync {
            if let hit = setups[key] {
                cached = hit
                return
            }
            if waiting[key] != nil {
                waiting[key]?.append(completion)
            } else {
                waiting[key] = [completion]
                shouldFetch = true
            }
        }
        // Outside the lock: the completion goes on to start a segment fetch,
        // and running that inside `queue.sync` would hold the serial queue
        // while the other track waits to look up a setup it already has.
        if let cached = cached {
            completion(cached)
            return
        }
        guard shouldFetch else { return }

        fetchInit(of: track, route: route) { data in
            let built = data.flatMap { parseSetup($0, of: track) }
            if built == nil {
                AppLog.hls("ts: \(track.path) setup failed")
            }
            var callbacks: [(LegacyTSTransmuxer.TrackSetup?) -> Void] = []
            queue.sync {
                if let built = built { setups[key] = built }
                callbacks = waiting.removeValue(forKey: key) ?? []
            }
            for callback in callbacks { callback(built) }
        }
    }

    private static func parseSetup(
        _ data: Data,
        of track: SABRDelivery.Track
    ) -> LegacyTSTransmuxer.TrackSetup? {
        guard let config = LegacyProgressiveRemux.parseInit(data) else {
            AppLog.hls("ts: \(track.path) init has no parsable moov")
            return nil
        }
        let isVideo = config.handler == "vide"
        if isVideo {
            guard let avc = LegacyTSTransmuxer.avcConfig(fromInit: data) else {
                AppLog.hls("ts: \(track.path) has no avcC; nothing would decode")
                return nil
            }
            AppLog.hls(
                "ts: \(track.path) video ts=\(config.timescale)"
                    + " sps=\(avc.sps.count) pps=\(avc.pps.count)"
                    + " nalLen=\(avc.nalLengthSize)"
            )
            return LegacyTSTransmuxer.TrackSetup(
                isVideo: true,
                timescale: config.timescale,
                avc: avc,
                aacObjectType: 0,
                aacRateIndex: 0,
                aacChannels: 0
            )
        }
        guard let aac = LegacyTSTransmuxer.aacConfig(fromInit: data) else {
            AppLog.hls("ts: \(track.path) has no usable esds")
            return nil
        }
        let rate = LegacyTSTransmuxer.aacRates[aac.rateIndex]
        AppLog.hls(
            "ts: \(track.path) audio ts=\(config.timescale)"
                + " objectType=\(aac.objectType) \(rate)Hz ch=\(aac.channels)"
        )
        return LegacyTSTransmuxer.TrackSetup(
            isVideo: false,
            timescale: config.timescale,
            avc: nil,
            aacObjectType: aac.objectType,
            aacRateIndex: aac.rateIndex,
            aacChannels: aac.channels
        )
    }

    // MARK: - Fetching

    private static func fetchInit(
        of track: SABRDelivery.Track,
        route: SABRDelivery.Route,
        completion: @escaping (Data?) -> Void
    ) {
        request("init", of: track, route: route, completion: completion)
    }

    private static func fetch(
        index: Int,
        of track: SABRDelivery.Track,
        route: SABRDelivery.Route,
        completion: @escaping (Data?) -> Void
    ) {
        request(String(index), of: track, route: route, completion: completion)
    }

    private static func request(
        _ name: String,
        of track: SABRDelivery.Track,
        route: SABRDelivery.Route,
        completion: @escaping (Data?) -> Void
    ) {
        guard let request = SABRDelivery.segmentRequest(name, of: track, route: route) else {
            AppLog.hls("ts: \(track.path)/\(name) has no request")
            completion(nil)
            return
        }
        route.fetcher.fetch(request) { result in
            switch result {
            case .success(let data):
                completion(data)
            case .failure(let error):
                AppLog.hls(
                    "ts: \(track.path)/\(name) fetch failed:"
                        + " \(error.localizedDescription)"
                )
                completion(nil)
            }
        }
    }
}
#endif
