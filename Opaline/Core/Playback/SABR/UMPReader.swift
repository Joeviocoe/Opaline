import Foundation

/// One UMP part: a type tag and its payload.
struct UMPPart {
    let type: Int
    let payload: Data
}

/// Part types we act on. The server sends plenty more; everything unlisted is
/// skipped, which is the documented way to stay forward-compatible with UMP.
/// Numbers are YouTube's own, cross-checked against two independent
/// implementations of this protocol (SmartTube's `UMPPartId`, LuanRT's
/// `googlevideo`) — an earlier guess had 43-45 and 57 shifted by one, which
/// made a server seek look like an expired player response.
enum UMPPartType: Int {
    case mediaHeader = 20
    case media = 21
    case mediaEnd = 22
    /// Readahead targets, backoff and the playback cookie — the server pacing
    /// the client. See `NextRequestPolicy` in googlevideo's protos.
    case nextRequestPolicy = 35
    /// Where a format ends: last segment number and end time.
    case formatInitializationMetadata = 42
    case sabrRedirect = 43
    case sabrError = 44
    case sabrSeek = 45
    case reloadPlayerResponse = 46
    /// Bookkeeping the server attaches to ordinary responses. Listed only so
    /// logs name them instead of printing bare numbers — a response carrying
    /// nothing but these was once mistaken for the end of the stream.
    case playbackStartPolicy = 47
    case requestIdentifier = 52
    case requestCancellationPolicy = 53
    case sabrContextUpdate = 57
    case streamProtectionStatus = 58
    case endOfTrack = 62
}

/// Incremental reader for UMP's length-prefixed framing.
///
/// A response is a flat run of `(type, size, payload)` triples, both numbers in
/// UMP's own varint — unrelated to protobuf's: the byte count is encoded in the
/// leading bits of the first byte, and the remaining bytes are little-endian.
final class UMPReader {
    /// The framing buffer is a plain byte array, not `Data`, and that is
    /// deliberate.
    ///
    /// This build bundles Xcode 12.5.1's Swift Foundation overlay and runs it
    /// against iOS 9.3's system Foundation. `buffer.append(chunk)` on an empty
    /// buffer lets `Data` adopt the bridged `NSData` that URLSession handed us,
    /// and the later `removeSubrange` then drives a representation transition
    /// the modern overlay assumes of a much newer Foundation. Measured on the
    /// device: a trap inside `Data._Representation.replaceSubrange`, reached
    /// from `readParts`, on the first SABR response. An array of bytes is pure
    /// Swift and has no bridged representation to transition.
    private var buffer: [UInt8] = []

    /// Refuses to grow without bound.
    ///
    /// A part is only emitted once its whole payload has arrived, so a bad size
    /// field would otherwise buffer for ever, and a multi-megabyte contiguous
    /// allocation is exactly what fails first on a 1 GB 32-bit device.
    private static let bufferLimit = 32 * 1024 * 1024

    /// UMP varint: byte count comes from the high bits of the first byte, the
    /// low bits carry the value's head, trailing bytes are little-endian.
    static func readVarint(_ data: [UInt8], _ offset: Int) -> (Int, Int)? {
        guard offset >= 0, offset < data.count else {
            return nil
        }
        let first = Int(data[offset])
        let length: Int
        switch first {
        case ..<128:
            length = 1
        case ..<192:
            length = 2
        case ..<224:
            length = 3
        case ..<240:
            length = 4
        default:
            length = 5
        }
        guard offset + length <= data.count else {
            return nil
        }
        // The 5-byte form drops the first byte entirely and is a plain uint32.
        // These are part sizes, so anything that cannot index the buffer is
        // malformed -- bound it rather than narrowing and trapping on armv7.
        guard length < 5 else {
            let wide = readLittleEndian(data, offset + 1, count: 4)
            guard wide <= UInt64(Int32.max) else {
                return nil
            }
            return (Int(wide), offset + 5)
        }
        let head = UInt64(first & (0xFF >> length))
        let tail = readLittleEndian(data, offset + 1, count: length - 1)
        // head occupies the low 8 - length bits, so `|` is the old `+`. Stay
        // in UInt64: the shifted product exceeds Int32 for the 4-byte form.
        let value = head | (tail << UInt64(8 - length))
        guard value <= UInt64(Int32.max) else {
            return nil
        }
        return (Int(value), offset + length)
    }

    private static func readLittleEndian(
        _ data: [UInt8],
        _ offset: Int,
        count: Int
    ) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<count {
            value |= UInt64(data[offset + index]) << (8 * index)
        }
        return value
    }

    func append(_ chunk: Data) {
        buffer.append(contentsOf: chunk)
    }

    /// Returns every part fully present in the buffer and consumes it. A part
    /// split across chunk boundaries stays buffered until the rest arrives.
    func readParts() -> [UMPPart] {
        var parts: [UMPPart] = []
        var offset = 0
        while true {
            // `afterSize + size` must never be formed: readVarint bounds each
            // value to Int32.max on its own, but their SUM still overflows a
            // 32-bit Int, and on armv7 that traps instead of wrapping. A server
            // sending a large size field then kills the process from inside a
            // URLSession callback. Subtracting instead keeps every intermediate
            // inside the buffer's own size. (Measured on the device: this is the
            // trap in UMPReader.readParts that ended every SABR playback.)
            guard let (type, afterType) = Self.readVarint(buffer, offset),
                  let (size, afterSize) = Self.readVarint(buffer, afterType),
                  size >= 0,
                  afterSize >= 0,
                  afterSize <= buffer.count,
                  size <= buffer.count - afterSize
            else {
                break
            }
            parts.append(UMPPart(
                type: type,
                payload: Data(buffer[afterSize..<(afterSize + size)])
            ))
            offset = afterSize + size
        }
        if offset > 0 {
            buffer.removeFirst(offset)
        }
        if buffer.count > Self.bufferLimit {
            // Loud, because silently dropping framing state desynchronises the
            // stream and every later part is then garbage.
            AppLog.onesie(
                "ump: buffer reached \(buffer.count / 1024) KB with no complete"
                    + " part; discarding — the stream is out of frame"
            )
            buffer.removeAll(keepingCapacity: false)
        }
        return parts
    }
}
