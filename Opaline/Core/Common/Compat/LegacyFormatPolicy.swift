import Foundation

#if LEGACY_IOS9
/// What an A5/A5X can actually decode.
///
/// The codec filter upstream applies is not enough here. Measured on an iPad 3,
/// the ladder offered for a normal video was:
///
///     1080p/137/avc1  ✗1080p/248/vp9  720p/136/avc1  ✗720p/247/vp9
///     480p/135/avc1   ✗480p/244/vp9   360p/134/avc1  ...
///
/// Every avc1 rung passes `fmtIsPlayableVideo`, so selection took itag 137 —
/// 1080p at `avc1.640028`, High profile **level 4.0**, 181 MB. The A5X's video
/// decoder tops out at H.264 High **4.1** and, in practice, 720p30; handing it
/// 1080p yields either a hard failure or a slideshow, and the failure looks like
/// a playback bug rather than a format one.
enum LegacyFormatPolicy {
    /// A5X hardware limit. 4.1 is the ceiling; 1080p30 is level 4.0 and would
    /// pass a level check alone, which is why the height cap is separate.
    static let maxLevel = 41
    /// Cap on the short edge: 1080 means 1920x1080 landscape or 1080x1920
    /// vertical.
    ///
    /// Raised from 720 as a measured experiment. Apple specs the iPad 3 for
    /// H.264 up to 1080p30 High 4.1 and itag 137 is `avc1.640028` — High level
    /// 4.0 — so this is inside the decoder's rating on paper. What is untested
    /// is everything around it: 1080p is ~2.07M pixels against 720p's 921k, the
    /// file is roughly 2.3x larger over a ~1.2 MB/s link, and the A5X was
    /// notoriously stretched driving its own 2048x1536 panel.
    ///
    /// The evidence to judge it by is already logged: time to FIRST FRAME,
    /// `[Perf] stall` durations during playback, and the RSS peak. If any of
    /// those degrade materially, put this back to 720 — the panel gains little
    /// from 1080p at normal viewing distance, and smoothness is worth more.
    static let maxHeight = 1_080
    static let maxFPS = 30

    static func accepts(mimeType: String, width: Int?, height: Int?, fps: Int?) -> Bool {
        // The cap is on the SHORT edge, not on height.
        //
        // Capping height assumes landscape. A vertical Short at 720x1280 has a
        // height of 1280, so a height cap rejected it — and 480p (480x854) and
        // even "1080p" (1080x1920) with it, leaving 360x640 as the best format
        // that passed. Every Short played at 360p, which is tolerable on a phone
        // and visibly soft on a 2048x1536 panel.
        //
        // Decode cost tracks pixel count, not orientation: 720x1280 is the same
        // ~921k pixels as 1280x720 and equally within H.264 level 4.1.
        let shortEdge = [width, height].compactMap { $0 }.min()
        if let shortEdge = shortEdge, shortEdge > maxHeight {
            return false
        }
        // 60 fps at any size is beyond this decoder, and YouTube only offers it
        // at 720p and above.
        if let fps = fps, fps > maxFPS {
            return false
        }
        guard let level = level(fromMimeType: mimeType) else {
            // No parseable codec string: let it through rather than silently
            // emptying the ladder. The height and fps caps still applied.
            return true
        }
        return level <= maxLevel
    }

    /// H.264 level from an `avc1.PPCCLL` codec string, as a decimal level×10.
    ///
    /// The three bytes after `avc1.` are profile_idc, constraint flags and
    /// level_idc in hex — `avc1.640028` is profile 0x64 (High), 0x00, level
    /// 0x28 = 40, i.e. level 4.0. Returns nil for anything that is not avc1 or
    /// is malformed.
    static func level(fromMimeType mime: String) -> Int? {
        guard let range = mime.range(of: "avc1.") else {
            return nil
        }
        let rest = mime[range.upperBound...]
        let code = rest.prefix { $0.isHexDigit }
        guard code.count >= 6 else {
            return nil
        }
        return Int(code.suffix(2), radix: 16)
    }
}
#endif
