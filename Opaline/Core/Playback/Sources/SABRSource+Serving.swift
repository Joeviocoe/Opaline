import AVFoundation
import Foundation

// MARK: - Serving the streams to AVPlayer

extension SABRSource {
    /// Routes one HTTP path to the bytes behind it.
    ///
    /// Paths are `/master.m3u8`, `/<track>.m3u8` and `/s/<track>/<n>` (or
    /// `/s/<track>/init`). Segment numbers come from the `sidx` in the init
    /// segment, so each one maps to a byte range of the same file the legacy
    /// URL would serve, and the session answers it.
    static func route(
        path: String,
        tracks: [Track],
        session: SABRSession,
        completion: @escaping (Data?, String) -> Void
    ) {
        let parts = path.split(separator: "/").map(String.init)
        if path == "/master.m3u8" {
            completion(Data(mainPlaylist(tracks: tracks).utf8), "application/vnd.apple.mpegurl")
            return
        }
        if parts.count == 1, parts[0].hasSuffix(".m3u8") {
            let name = String(parts[0].dropLast(5))
            guard let track = tracks.first(where: { $0.path == name }) else {
                completion(nil, "")
                return
            }
            let playlist = HLSGenerator.segmentedPlaylist(
                base: "/s/\(track.path)", segments: track.segments
            )
            completion(Data(playlist.utf8), "application/vnd.apple.mpegurl")
            return
        }
        guard parts.count == 3, parts[0] == "s",
              let track = tracks.first(where: { $0.path == parts[1] }) else {
            completion(nil, "")
            return
        }
        serveSegment(parts[2], of: track, session: session, completion: completion)
    }

    /// Main playlist pointing at the two media playlists.
    static func mainPlaylist(tracks: [Track]) -> String {
        guard let video = tracks.first, let audio = tracks.last, tracks.count == 2 else {
            return ""
        }
        let audioPeak = HLSGenerator.peakBitrate(
            audio.segments, fallback: audio.format.bitrate
        )
        let videoPeak = HLSGenerator.peakBitrate(
            video.segments, fallback: video.format.bitrate
        )
        return HLSGenerator.mainPlaylist(
            bandwidth: videoPeak + audioPeak,
            codecs: "\(video.format.codecs),\(audio.format.codecs)",
            resolution: "\(video.format.width ?? 1_280)x\(video.format.height ?? 720)",
            uris: HLSGenerator.PlaylistURIs(
                video: "/\(video.path).m3u8",
                audio: "/\(audio.path).m3u8"
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

    /// Pairs each format with its segment index. The init segment carries the
    /// `sidx`, so both come out of what the session already fetched.
    static func tracks(inits: [Int: Data], info: DirectPlaybackInfo) -> [Track]? {
        guard let video = info.dashVideoFormat,
              let audio = info.dashAudioFormat,
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

    /// Brings up the loopback server and hands AVPlayer its playlist URL.
    func buildPlayback(
        session: SABRSession,
        inits: [Int: Data],
        info: DirectPlaybackInfo,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let tracks = Self.tracks(inits: inits, info: info) else {
            completion(.failure(SABRError.noInitSegment))
            return
        }
        let server = LocalMediaServer { path, done in
            Self.route(path: path, tracks: tracks, session: session, completion: done)
        }
        guard let server else {
            completion(.failure(SABRError.server("could not start the local server")))
            return
        }
        self.server = server
        server.start { base in
            guard let url = base.map({ $0.appendingPathComponent("master.m3u8") }) else {
                completion(.failure(SABRError.server("local server did not come up")))
                return
            }
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            // Left at the default: lowering `preferredForwardBufferDuration`
            // for SABR changed nothing — AVPlayer treats it as a hint for HLS
            // and kept 20-25s of buffer health regardless (device-checked).
            PlaybackBufferPolicy.configure(item: item)
            completion(.success(PreparedPlayback(
                item: item,
                captions: info.captionTracks,
                duration: info.duration
            )))
        }
    }
}
