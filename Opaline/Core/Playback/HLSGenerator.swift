import Foundation
import AVFoundation

struct SidxSegment {
    let offset: Int64
    let size: Int64
    let duration: Double
}

enum HLSGenerator {
    // MARK: - Subtypes

    struct PlaylistURIs {
        let video: String
        let audio: String
    }

    struct SidxHeader {
        let timescale: UInt32
        let referenceCount: Int
        let referencesStart: Int
    }

    // MARK: - Properties

    static let scheme = "ytv-hls"

    // MARK: - HLS playlist generation

    /// Generate a media playlist with byte-range segments.
    /// `startAt` means what it does for [[segmentedPlaylist]]: the player
    /// begins there instead of buffering the opening and being seeked away
    /// from it the moment the item turns ready.
    static func mediaPlaylist(
        url: URL,
        initBytes: Int,
        dataStartOffset: Int64,
        segments: [SidxSegment],
        startAt: Double? = nil
    ) -> String {
        let maxDur = segments.map(\.duration).max() ?? 5
        let urlStr = url.absoluteString
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        let target = Int(ceil(maxDur))
        lines.append("#EXT-X-TARGETDURATION:\(target)")
        lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
        lines.append(contentsOf: startTag(startAt))
        let mapTag = "#EXT-X-MAP:URI=\"\(urlStr)\""
            + ",BYTERANGE=\"\(initBytes)@0\""
        lines.append(mapTag)
        for segment in segments {
            let off = dataStartOffset + segment.offset
            let inf = String(
                format: "#EXTINF:%.3f,",
                segment.duration
            )
            lines.append(inf)
            lines.append(
                "#EXT-X-BYTERANGE:\(segment.size)@\(off)"
            )
            lines.append(urlStr)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Media playlist addressing one URL per segment instead of byte ranges.
    ///
    /// SABR delivers a sequential stream, so the player must ask for segments
    /// in order — byte ranges over a single URL let it seek around the file and
    /// leave the session fetching megabytes to reach an offset.
    /// `startAt` becomes an `EXT-X-START` tag, telling the player where to
    /// begin. Without it a freshly attached item buffers from zero and only
    /// then honours the seek — so a mid-video quality switch fetches the
    /// opening segments nobody will watch, and the session gets dragged back
    /// and forth between the start and the playhead.
    static func segmentedPlaylist(
        base: String,
        segments: [SidxSegment],
        startAt: Double? = nil
    ) -> String {
        let maxDur = segments.map(\.duration).max() ?? 5
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7"]
        lines.append("#EXT-X-TARGETDURATION:\(Int(ceil(maxDur)))")
        lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
        lines.append(contentsOf: startTag(startAt))
        lines.append("#EXT-X-MAP:URI=\"\(base)/init\"")
        for (index, segment) in segments.enumerated() {
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append("\(base)/\(index)")
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `EXT-X-START` when there is somewhere to start, nothing when there is
    /// not — playlists differ only in whether they carry the tag.
    private static func startTag(_ startAt: Double?) -> [String] {
        guard let startAt = startAt, startAt > 0 else {
            return []
        }
        let tag = String(
            format: "#EXT-X-START:TIME-OFFSET=%.3f,PRECISE=YES", startAt
        )
        return [tag]
    }

    /// Generate an audio-only main playlist.
    static func audioOnlyMainPlaylist(
        audioCodecs: String,
        audioBandwidth: Int,
        audioPlaylistURI: String
    ) -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        let streamInf = "#EXT-X-STREAM-INF:"
            + "BANDWIDTH=\(audioBandwidth)"
            + ",CODECS=\"\(audioCodecs)\""
        lines.append(streamInf)
        lines.append(audioPlaylistURI)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Generate a main playlist with video and audio.
    static func mainPlaylist(
        bandwidth: Int,
        codecs: String,
        resolution: String,
        uris: PlaylistURIs
    ) -> String {
        var lines: [String] = []
        lines.append("#EXTM3U")
        lines.append("#EXT-X-VERSION:7")
        lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
        let mediaTag = "#EXT-X-MEDIA:TYPE=AUDIO"
            + ",GROUP-ID=\"audio\",NAME=\"Main\""
            + ",DEFAULT=YES,AUTOSELECT=YES"
            + ",URI=\"\(uris.audio)\""
        lines.append(mediaTag)
        let streamInf = "#EXT-X-STREAM-INF:"
            + "BANDWIDTH=\(bandwidth)"
            + ",CODECS=\"\(codecs)\""
            + ",RESOLUTION=\(resolution)"
            + ",AUDIO=\"audio\""
        lines.append(streamInf)
        lines.append(uris.video)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `BANDWIDTH` must be an upper bound on every segment's rate, audio
    /// rendition included — YouTube's `bitrate` is the video average, so VBR
    /// peaks overshoot it and AVPlayer logs -12318 ("Segment exceeds specified
    /// bandwidth for variant"). SIDX gives us each segment's real size, so take
    /// the actual peak instead of guessing a headroom factor.
    static func peakBitrate(
        _ segments: [SidxSegment],
        fallback: Int
    ) -> Int {
        let peak = segments.reduce(0) { best, segment in
            guard segment.duration > 0 else {
                return best
            }
            return max(best, Int(Double(segment.size) * 8 / segment.duration))
        }
        return peak > 0 ? peak : fallback
    }

    // MARK: - Helpers

    static func readBigUInt16(
        data: Data,
        at offset: Int
    ) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            return 0
        }
        return UInt16(data.byte(at: offset)) << 8
            | UInt16(data.byte(at: offset + 1))
    }
}
