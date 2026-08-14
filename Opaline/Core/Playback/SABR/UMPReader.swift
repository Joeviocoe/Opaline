import Foundation

/// One UMP part: a type tag and its payload.
struct UMPPart {
    let type: Int
    let payload: Data
}

/// Part types we act on. The server sends plenty more; everything unlisted is
/// skipped, which is the documented way to stay forward-compatible with UMP.
enum UMPPartType: Int {
    case mediaHeader = 20
    case media = 21
    case mediaEnd = 22
    /// Carries the playback cookie in field 7 and the readahead targets.
    /// Verified on device 2026-08-14: the server sends 35, not 36.
    case nextRequestPolicy = 35
    case nextRequestPolicyAlt = 36
    case formatInitializationMetadata = 42
    case sabrError = 43
    case sabrSeek = 44
    case reloadPlayerResponse = 45
    case streamProtectionStatus = 57
}

/// Incremental reader for UMP's length-prefixed framing.
///
/// A response is a flat run of `(type, size, payload)` triples, both numbers in
/// UMP's own varint — unrelated to protobuf's: the byte count is encoded in the
/// leading bits of the first byte, and the remaining bytes are little-endian.
final class UMPReader {
    private var buffer = Data()

    /// UMP varint: byte count comes from the high bits of the first byte, the
    /// low bits carry the value's head, trailing bytes are little-endian.
    static func readVarint(_ data: Data, _ offset: Int) -> (Int, Int)? {
        guard offset >= 0, offset < data.count else {
            return nil
        }
        let first = Int(data[data.startIndex + offset])
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
        guard length < 5 else {
            return (Int(readLittleEndian(data, offset + 1, count: 4)), offset + 5)
        }
        let head = first & (0xFF >> length)
        let tail = readLittleEndian(data, offset + 1, count: length - 1)
        return (head + Int(tail) << (8 - length), offset + length)
    }

    private static func readLittleEndian(
        _ data: Data,
        _ offset: Int,
        count: Int
    ) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<count {
            value |= UInt64(data[data.startIndex + offset + index]) << (8 * index)
        }
        return value
    }

    func append(_ chunk: Data) {
        buffer.append(chunk)
    }

    /// Returns every part fully present in the buffer and consumes it. A part
    /// split across chunk boundaries stays buffered until the rest arrives.
    func readParts() -> [UMPPart] {
        var parts: [UMPPart] = []
        var offset = 0
        while true {
            guard let (type, afterType) = Self.readVarint(buffer, offset),
                  let (size, afterSize) = Self.readVarint(buffer, afterType),
                  size >= 0, afterSize + size <= buffer.count
            else {
                break
            }
            // Offsets here are relative to the buffer's contents, and Data is
            // not always indexed from zero once bytes have been dropped off
            // the front — so every subrange is built off startIndex.
            let base = buffer.startIndex + afterSize
            parts.append(UMPPart(type: type, payload: buffer.subdata(in: base..<(base + size))))
            offset = afterSize + size
        }
        if offset > 0 {
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + offset))
        }
        return parts
    }
}
