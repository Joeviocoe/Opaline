import Foundation

// MARK: - Playlist browse-params protobuf decoding

extension InnertubeClient {
    /// Library playlist tabs carry the playlist id inside a base64 protobuf
    /// `params` blob (field 70) instead of a plain browse id.
    static func extractPlaylistIdFromParams(
        _ params: String
    ) -> String? {
        guard let urlDecoded = params.removingPercentEncoding,
              let data = Data(
                  base64Encoded: urlDecoded,
                  options: .ignoreUnknownCharacters
              )
        else {
            return nil
        }
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let tagResult = decodeVarint(bytes: bytes, offset: &offset)
            let fieldNum = tagResult >> 3
            let wireType = tagResult & 0x7
            switch wireType {
            case 0:
                skipVarint(bytes: bytes, offset: &offset)
            case 2:
                if let id = decodeLengthDelimited(
                    bytes: bytes,
                    offset: &offset,
                    fieldNum: fieldNum
                ) {
                    return id
                }
            default:
                return nil
            }
        }
        return nil
    }

    static func decodeVarint(
        bytes: [UInt8],
        offset: inout Int
    ) -> UInt64 {
        var value: UInt64 = 0
        var shift = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7f) << shift
            shift += 7
            if byte & 0x80 == 0 {
                break
            }
        }
        return value
    }

    static func skipVarint(
        bytes: [UInt8],
        offset: inout Int
    ) {
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte & 0x80 == 0 {
                break
            }
        }
    }

    static func decodeLengthDelimited(
        bytes: [UInt8],
        offset: inout Int,
        fieldNum: UInt64
    ) -> String? {
        guard offset < bytes.count else {
            return nil
        }
        let len = Int(bytes[offset])
        offset += 1
        guard offset + len <= bytes.count else {
            return nil
        }
        let slice = bytes[offset..<offset + len]
        if fieldNum == 70,
           let id = String(bytes: slice, encoding: .utf8),
           id.hasPrefix("PL") || id == "LL" {
            return id
        }
        offset += len
        return nil
    }
}
