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
    static let maxHeight = 720
    static let maxFPS = 30

    static func accepts(mimeType: String, height: Int?, fps: Int?) -> Bool {
        if let height = height, height > maxHeight {
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
