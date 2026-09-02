import Foundation

#if LEGACY_IOS9
/// Just enough ISO-BMFF to turn a fragmented MP4 into a progressive one.
///
/// **Why any of this exists.** AVFoundation derives a fragmented MP4's timing by
/// visiting every `moof` in the file. Measured on an iPad 3: 40 MB read and the
/// parse still unfinished, ~30 s before playback is smooth, and at ~1.2 MB/s
/// there is no tuning below that — the bytes themselves are the cost.
///
/// A progressive MP4 states everything up front in one `moov`, so the player
/// reads a single index and then streams linearly. Every input needed to build
/// that `moov` is already fetched: the init segment, the `sidx`, and all the
/// `moof` headers that index priming pulls in a few seconds.
enum MP4Box {
    /// One box: its type, its payload range, and where the next one starts.
    struct Header {
        let type: String
        let payloadStart: Int
        let payloadEnd: Int
        let next: Int
    }

    /// Reads a box header at `offset`, or nil if the data runs out.
    ///
    /// Handles the 64-bit `largesize` form: a `mdat` above 4 GB uses it, and
    /// misreading it walks off into nonsense.
    static func header(in data: Data, at offset: Int) -> Header? {
        let base = data.startIndex
        guard offset >= 0, offset + 8 <= data.count else {
            return nil
        }
        // Everything stays in Int64 until it is known to fit.
        //
        // `Int(be32(...))` is a trap on armv7, where Int is 32-bit: a box size
        // with the top bit set — which is what garbage, or a misaligned read,
        // usually looks like — kills the process instead of converting. That is
        // exactly how this crashed the first time it met a byte range that was
        // not a real box header.
        guard let rawSize = be32(data, base + offset) else {
            return nil
        }
        var size = Int64(rawSize)
        guard let type = ascii(data, base + offset + 4, length: 4) else {
            return nil
        }
        var payloadStart = offset + 8
        if size == 1 {
            guard offset + 16 <= data.count, let large = be64(data, base + offset + 8) else {
                return nil
            }
            size = Int64(bitPattern: large)
            payloadStart = offset + 16
        } else if size == 0 {
            size = Int64(data.count - offset)
        }
        // Reject anything that cannot be a box in this buffer before it is
        // narrowed to Int.
        guard size >= 8,
              size <= Int64(data.count),
              Int64(offset) + size <= Int64(data.count) else {
            return nil
        }
        let sizeInt = Int(size)
        guard payloadStart <= offset + sizeInt else {
            return nil
        }
        return Header(
            type: type,
            payloadStart: payloadStart,
            payloadEnd: offset + sizeInt,
            next: offset + sizeInt
        )
    }

    /// Every direct child of the region, in order.
    static func children(of data: Data, from: Int, to: Int) -> [Header] {
        var boxes: [Header] = []
        var cursor = from
        while cursor < to, let box = header(in: data, at: cursor) {
            boxes.append(box)
            cursor = box.next
        }
        return boxes
    }

    /// First descendant matching a `/`-separated path, e.g. `moov/trak/mdia`.
    static func find(_ path: String, in data: Data, from: Int = 0, to: Int? = nil) -> Header? {
        let names = path.split(separator: "/").map(String.init)
        var start = from
        var end = to ?? data.count
        var found: Header?
        for name in names {
            found = children(of: data, from: start, to: end).first { $0.type == name }
            guard let box = found else {
                return nil
            }
            start = box.payloadStart
            end = box.payloadEnd
        }
        return found
    }

    // MARK: - Reading

    /// Bounds-checked big-endian reads.
    ///
    /// These return nil rather than trapping: every offset here is derived from
    /// bytes off the network, so "this index is valid" is an assumption the data
    /// is free to violate. An unchecked `data[index]` on a short buffer is a
    /// crash, and on armv7 it looks identical to the integer traps this port has
    /// already hit twice.
    static func be32(_ data: Data, _ index: Int) -> UInt32? {
        guard index >= data.startIndex, index + 4 <= data.endIndex else {
            return nil
        }
        return UInt32(data[index]) << 24 | UInt32(data[index + 1]) << 16
            | UInt32(data[index + 2]) << 8 | UInt32(data[index + 3])
    }

    static func be64(_ data: Data, _ index: Int) -> UInt64? {
        guard index >= data.startIndex, index + 8 <= data.endIndex else {
            return nil
        }
        return (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(data[index + $1]) }
    }

    /// Fixed-length ASCII, or nil if it does not fit.
    static func ascii(_ data: Data, _ index: Int, length: Int) -> String? {
        guard index >= data.startIndex, index + length <= data.endIndex else {
            return nil
        }
        return String(bytes: data[index..<(index + length)], encoding: .ascii)
    }

    // MARK: - Writing

    /// A box with its size prefix, built from already-encoded payload.
    static func box(_ type: String, _ payload: Data) -> Data {
        var out = Data()
        out.append(u32(UInt32(payload.count + 8)))
        out.append(contentsOf: Array(type.utf8))
        out.append(payload)
        return out
    }

    /// A full box: version and flags ahead of the payload.
    static func fullBox(_ type: String, version: UInt8, flags: UInt32, _ payload: Data) -> Data {
        var body = Data([version])
        body.append(contentsOf: [
            UInt8((flags >> 16) & 0xFF), UInt8((flags >> 8) & 0xFF), UInt8(flags & 0xFF),
        ])
        body.append(payload)
        return box(type, body)
    }

    static func u32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ])
    }

    static func u16(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
#endif
