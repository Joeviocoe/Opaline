import Foundation

/// Just enough protobuf to talk to SABR: we write `VideoPlaybackAbrRequest` and
/// read a handful of fields back out of UMP parts. Nothing here knows the schema
/// — field numbers live at the call sites, next to the message they belong to.
enum Protobuf {
    /// Field number to values, flattened — repeated fields keep every value and
    /// groups (wire type 3/4, which SABR never sends) abort the parse.
    enum Value {
        case number(Int)
        case data(Data)
    }

    // MARK: - Writing

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var out = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            out.append(byte)
        } while value != 0
        return out
    }

    static func tag(_ field: Int, _ wire: Int) -> Data {
        varint(UInt64(field << 3 | wire))
    }

    static func int(_ field: Int, _ value: Int) -> Data {
        tag(field, 0) + varint(UInt64(max(value, 0)))
    }

    static func bool(_ field: Int, _ value: Bool) -> Data {
        int(field, value ? 1 : 0)
    }

    static func float(_ field: Int, _ value: Float) -> Data {
        var bits = value.bitPattern.littleEndian
        return tag(field, 5) + Data(bytes: &bits, count: 4)
    }

    static func bytes(_ field: Int, _ value: Data) -> Data {
        tag(field, 2) + varint(UInt64(value.count)) + value
    }

    static func string(_ field: Int, _ value: String) -> Data {
        bytes(field, Data(value.utf8))
    }

    // MARK: - Reading

    static func parse(_ data: Data) -> [Int: [Value]] {
        var fields: [Int: [Value]] = [:]
        var offset = 0
        while offset < data.count {
            guard let (key, afterKey) = readVarint(data, offset) else {
                break
            }
            guard let (value, next) = readValue(data, afterKey, wire: Int(key) & 7) else {
                break
            }
            fields[Int(key) >> 3, default: []].append(value)
            offset = next
        }
        return fields
    }

    private static func readValue(
        _ data: Data,
        _ offset: Int,
        wire: Int
    ) -> (Value, Int)? {
        switch wire {
        case 0:
            guard let (value, next) = readVarint(data, offset) else {
                return nil
            }
            return (.number(Int(value)), next)
        case 1:
            return slice(data, offset, count: 8).map { (.data($0.0), $0.1) }
        case 2:
            guard let (length, afterLength) = readVarint(data, offset) else {
                return nil
            }
            return slice(data, afterLength, count: Int(length)).map { (.data($0.0), $0.1) }
        case 5:
            return slice(data, offset, count: 4).map { (.data($0.0), $0.1) }
        default:
            return nil
        }
    }

    private static func slice(_ data: Data, _ offset: Int, count: Int) -> (Data, Int)? {
        guard count >= 0, offset + count <= data.count else {
            return nil
        }
        let start = data.startIndex + offset
        return (data.subdata(in: start..<(start + count)), offset + count)
    }

    static func readVarint(_ data: Data, _ offset: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var offset = offset
        while offset < data.count, shift < 64 {
            let byte = data[data.startIndex + offset]
            value |= UInt64(byte & 0x7F) << shift
            offset += 1
            if byte & 0x80 == 0 {
                return (value, offset)
            }
            shift += 7
        }
        return nil
    }
}

extension Dictionary where Key == Int, Value == [Protobuf.Value] {
    func number(_ field: Int) -> Int? {
        guard case .number(let value)? = self[field]?.first else {
            return nil
        }
        return value
    }

    func data(_ field: Int) -> Data? {
        guard case .data(let value)? = self[field]?.first else {
            return nil
        }
        return value
    }
}
