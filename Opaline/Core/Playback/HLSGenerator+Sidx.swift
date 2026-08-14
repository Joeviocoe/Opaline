import Foundation

// MARK: - sidx parsing

extension HLSGenerator {
    /// Parse a sidx box from raw data.
    static func parseSidx(data: Data) -> [SidxSegment]? {
        var pos = 0
        while pos + 8 <= data.count {
            var boxSize = Int64(data.readBigUInt32(at: pos))
            let boxType = data.readFourCC(at: pos + 4)
            if boxSize == 1, pos + 16 <= data.count {
                boxSize = Int64(
                    bitPattern: data.readBigUInt64(at: pos + 8)
                )
            }
            guard boxSize >= 8 else { break }
            if boxType == "sidx" {
                let clamped = Int(
                    min(boxSize, Int64(data.count - pos))
                )
                return parseSidxContent(
                    data: data,
                    boxStart: pos,
                    boxSize: clamped
                )
            }
            pos += Int(boxSize)
        }
        return nil
    }

    private static func parseSidxHeader(
        data: Data,
        boxStart: Int,
        boxEnd: Int
    ) -> SidxHeader? {
        var pos = boxStart + 8
        guard pos + 4 <= boxEnd else {
            return nil
        }
        let version = data.byte(at: pos)
        pos += 4
        guard pos + 8 <= boxEnd else {
            return nil
        }
        let timescale = data.readBigUInt32(at: pos + 4)
        guard timescale > 0 else {
            return nil
        }
        pos += 8
        let timeFieldSize = version == 0 ? 8 : 16
        guard pos + timeFieldSize <= boxEnd else {
            return nil
        }
        pos += timeFieldSize
        guard pos + 4 <= boxEnd else {
            return nil
        }
        pos += 2
        let refCount = Int(readBigUInt16(data: data, at: pos))
        pos += 2
        return SidxHeader(
            timescale: timescale,
            referenceCount: refCount,
            referencesStart: pos
        )
    }

    private static func parseSidxContent(
        data: Data,
        boxStart: Int,
        boxSize: Int
    ) -> [SidxSegment]? {
        let boxEnd = boxStart + boxSize
        guard let header = parseSidxHeader(
            data: data,
            boxStart: boxStart,
            boxEnd: boxEnd
        ) else {
            return nil
        }
        var segments: [SidxSegment] = []
        segments.reserveCapacity(header.referenceCount)
        var currentOffset: Int64 = 0
        var pos = header.referencesStart
        for _ in 0..<header.referenceCount {
            guard pos + 12 <= boxEnd else { break }
            let refWord = data.readBigUInt32(at: pos)
            let refSize = Int64(refWord & 0x7FFF_FFFF)
            pos += 4
            let subDur = data.readBigUInt32(at: pos)
            pos += 8
            let dur = Double(subDur) / Double(header.timescale)
            segments.append(SidxSegment(
                offset: currentOffset,
                size: refSize,
                duration: dur
            ))
            currentOffset += refSize
        }
        return segments.isEmpty ? nil : segments
    }
}
