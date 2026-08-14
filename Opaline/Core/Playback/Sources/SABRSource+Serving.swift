import AVFoundation
import Foundation

// MARK: - Serving the streams to AVPlayer

extension SABRSource {
    /// What the server currently serves: one session and its two tracks.
    struct Route {
        let generation: Int
        let tracks: [Track]
        let session: SABRSession
        /// Where playback should pick up, for `EXT-X-START`.
        let startAt: Double?
    }

    /// Routes one HTTP path to the bytes behind it.
    ///
    /// Paths are `/g<n>/master.m3u8`, `/g<n>/<track>.m3u8` and
    /// `/g<n>/s/<track>/<index>` (or `.../init`). The generation is what makes
    /// a quality switch work on one server: AVPlayer caches playlists per URL,
    /// so reusing paths would hand it the previous playlist. Requests for a
    /// retired generation are refused — that item is gone.
    static func route(
        path: String,
        route: Route?,
        completion: @escaping (Data?, String) -> Void
    ) {
        let parts = path.split(separator: "/").map(String.init)
        guard let route, parts.first == "g\(route.generation)" else {
            completion(nil, "")
            return
        }
        let rest = Array(parts.dropFirst())
        let playlistType = "application/vnd.apple.mpegurl"
        if rest == ["master.m3u8"] {
            completion(Data(mainPlaylist(route: route).utf8), playlistType)
            return
        }
        if rest.count == 1, rest[0].hasSuffix(".m3u8") {
            let name = String(rest[0].dropLast(5))
            completion(mediaPlaylist(named: name, route: route), playlistType)
            return
        }
        guard rest.count == 3, rest[0] == "s",
              let track = route.tracks.first(where: { $0.path == rest[1] }) else {
            completion(nil, "")
            return
        }
        serveSegment(rest[2], of: track, session: route.session, completion: completion)
    }

    /// One track's playlist, or nil when the name is not one of ours.
    static func mediaPlaylist(named name: String, route: Route) -> Data? {
        guard let track = route.tracks.first(where: { $0.path == name }) else {
            return nil
        }
        return Data(HLSGenerator.segmentedPlaylist(
            base: "/g\(route.generation)/s/\(track.path)",
            segments: track.segments,
            startAt: route.startAt
        ).utf8)
    }

    /// Main playlist pointing at the two media playlists.
    static func mainPlaylist(route: Route) -> String {
        guard route.tracks.count == 2,
              let video = route.tracks.first,
              let audio = route.tracks.last else {
            return ""
        }
        let audioPeak = HLSGenerator.peakBitrate(audio.segments, fallback: audio.format.bitrate)
        let videoPeak = HLSGenerator.peakBitrate(video.segments, fallback: video.format.bitrate)
        return HLSGenerator.mainPlaylist(
            bandwidth: videoPeak + audioPeak,
            codecs: "\(video.format.codecs),\(audio.format.codecs)",
            resolution: "\(video.format.width ?? 1_280)x\(video.format.height ?? 720)",
            uris: HLSGenerator.PlaylistURIs(
                video: "/g\(route.generation)/\(video.path).m3u8",
                audio: "/g\(route.generation)/\(audio.path).m3u8"
            )
        )
    }

    private static func serveSegment(
        _ name: String,
        of track: Track,
        session: SABRSession,
        completion: @escaping (Data?, String) -> Void
    ) {
        let range: (offset: Int64, length: Int)
        if name == "init" {
            // Everything before the first media byte: ftyp, moov and sidx.
            range = (0, track.format.indexRangeEnd + 1)
        } else if let index = Int(name), index < track.segments.count {
            range = (segmentOffset(index, in: track), Int(track.segments[index].size))
        } else {
            completion(nil, "")
            return
        }
        session.read(SABRReadRequest(
            itag: track.format.itag,
            offset: range.offset,
            length: range.length,
            timeMs: timeMs(at: range.offset, in: track)
        )) { result in
            switch result {
            case .success(let data):
                completion(data, "video/mp4")
            case .failure(let error):
                AppLog.hls("segment \(track.path)/\(name) failed: \(error.localizedDescription)")
                completion(nil, "")
            }
        }
    }

    /// Byte offset of a segment: the media data starts after the index, and
    /// every segment before it takes up its own size.
    static func segmentOffset(_ index: Int, in track: Track) -> Int64 {
        var offset = Int64(track.format.indexRangeEnd + 1)
        for segment in track.segments.prefix(index) {
            offset += segment.size
        }
        return offset
    }

    /// Where a byte offset falls on the timeline, so a seek can restart the
    /// session at that point rather than streaming forward to it.
    static func timeMs(at offset: Int64, in track: Track) -> Int {
        var position = Int64(track.format.indexRangeEnd + 1)
        var elapsed = 0.0
        for segment in track.segments {
            if offset < position + segment.size {
                return Int(elapsed * 1_000)
            }
            position += segment.size
            elapsed += segment.duration
        }
        return Int(elapsed * 1_000)
    }

    /// Pairs each format with its segment index, taking the video format the
    /// session actually runs rather than the response's default — a quality
    /// switch changes the former only, and building playlists from the latter
    /// meant the picture never changed no matter what was selected.
    static func tracks(
        inits: [Int: Data],
        info: DirectPlaybackInfo,
        video: DashFormatInfo
    ) -> [Track]? {
        guard let audio = info.dashAudioFormat,
              let videoInit = inits[video.itag],
              let audioInit = inits[audio.itag],
              let videoSegments = HLSGenerator.parseSidx(data: videoInit),
              let audioSegments = HLSGenerator.parseSidx(data: audioInit) else {
            return nil
        }
        return [
            Track(format: video, segments: videoSegments, path: "video"),
            Track(format: audio, segments: audioSegments, path: "audio")
        ]
    }

    /// Points the server at a new session and hands AVPlayer its playlist URL.
    ///
    /// One server outlives the sessions it serves: a quality switch swaps what
    /// it routes to instead of starting another listener. Starting a listener
    /// per switch leaked a socket set each time, and once enough had leaked new
    /// listeners stopped coming up at all — which showed up as quality
    /// switching doing nothing.
    func buildPlayback(
        _ stream: Stream,
        session: SABRSession,
        inits: [Int: Data],
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let info = stream.info
        guard let tracks = Self.tracks(inits: inits, info: info, video: stream.video) else {
            completion(.failure(SABRError.noInitSegment))
            return
        }
        // Everything below touches state the server reads: the generation
        // counter, the server handle and its base URL. This runs on the
        // session's queue, so it is pinned to main to keep a single writer.
        DispatchQueue.main.async {
            self.attach(tracks: tracks, session: session, info: info, completion: completion)
        }
    }

    private func attach(
        tracks: [Track],
        session: SABRSession,
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        generation += 1
        route = Route(
            generation: generation,
            tracks: tracks,
            session: session,
            startAt: pendingStartAt
        )
        pendingStartAt = nil
        let path = "g\(generation)/master.m3u8"
        withServer { base in
            guard let base else {
                completion(.failure(SABRError.server("local server did not come up")))
                return
            }
            let item = AVPlayerItem(asset: AVURLAsset(url: base.appendingPathComponent(path)))
            PlaybackBufferPolicy.configure(item: item)
            completion(.success(PreparedPlayback(
                item: item,
                captions: info.captionTracks,
                duration: info.duration
            )))
        }
    }

    /// The single server for this source, started on first use.
    private func withServer(_ completion: @escaping (URL?) -> Void) {
        if let base = serverBase {
            completion(base)
            return
        }
        let server = LocalMediaServer { [weak self] path, done in
            Self.route(path: path, route: self?.route, completion: done)
        }
        guard let server else {
            completion(nil)
            return
        }
        self.server = server
        server.start { [weak self] base in
            DispatchQueue.main.async {
                self?.serverBase = base
                completion(base)
            }
        }
    }
}
