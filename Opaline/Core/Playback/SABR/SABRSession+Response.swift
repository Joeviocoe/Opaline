import Foundation

/// `MEDIA_HEADER` — what the following `MEDIA` parts belong to.
private struct MediaHeader {
    let itag: Int
    let startRange: Int64
    let sequence: Int
    let isInit: Bool
    let bufferedMs: Int

    /// Fields 1/3/6/8/9/15 of the message; 15 is a `TimeRange` whose own fields
    /// are start, duration and timescale.
    init?(_ payload: Data) {
        let fields = Protobuf.parse(payload)
        guard let itag = fields.number(3) else {
            return nil
        }
        self.itag = itag
        startRange = Int64(fields.number(6) ?? 0)
        sequence = fields.number(9) ?? 0
        isInit = (fields.number(8) ?? 0) != 0
        guard let range = fields.data(15) else {
            bufferedMs = 0
            return
        }
        let time = Protobuf.parse(range)
        let scale = time.number(3) ?? 1_000
        let start = time.number(1) ?? 0
        let duration = time.number(2) ?? 0
        bufferedMs = scale > 0 ? (start + duration) * 1_000 / scale : 0
    }
}

extension SABRSession {
    /// Folds one response into the session: media into the buffer, policy into
    /// the state carried by the next request.
    func consume(_ response: HTTPResponse) -> Result<Void, Error> {
        guard response.status == 200 else {
            AppLog.hls("sabr HTTP \(response.status)")
            return .failure(SABRError.server("HTTP \(response.status)"))
        }
        let reader = UMPReader()
        reader.append(response.data)
        var headers: [Int: MediaHeader] = [:]
        var sawMedia = false

        let parts = reader.readParts()
        for part in parts {
            if let failure = failure(in: part) {
                return .failure(failure)
            }
            sawMedia = apply(part, headers: &headers) || sawMedia
        }
        let reached = headers.values
            .filter { !$0.isInit }
            .map { "\($0.itag):seq\($0.sequence)" }
            .sorted()
            .joined(separator: " ")
        AppLog.hls("sabr got \(reached.isEmpty ? "no media" : reached)")
        if !sawMedia {
            // No media at all means the server declined rather than the stream
            // ending — some videos are simply not served over SABR, and the
            // part types say which case this is.
            AppLog.hls("sabr declined, parts: \(parts.map(\.type))")
            markEnded()
        }
        return .success(())
    }

    /// Applies one part; returns whether it carried media.
    private func apply(_ part: UMPPart, headers: inout [Int: MediaHeader]) -> Bool {
        switch UMPPartType(rawValue: part.type) {
        case .mediaHeader:
            // Field 1 is the header id the MEDIA parts refer back to.
            let id = Protobuf.parse(part.payload).number(1) ?? 0
            headers[id] = MediaHeader(part.payload)
        case .media:
            return store(media: part.payload, headers: headers)
        case .nextRequestPolicy, .nextRequestPolicyAlt:
            if let cookie = Protobuf.parse(part.payload).data(7) {
                setPlaybackCookie(cookie)
            }
        default:
            break
        }
        return false
    }

    /// The two parts that mean the session cannot continue as it stands.
    private func failure(in part: UMPPart) -> Error? {
        switch UMPPartType(rawValue: part.type) {
        case .sabrError:
            let fields = Protobuf.parse(part.payload)
            let text = String(data: part.payload.prefix(80), encoding: .isoLatin1) ?? ""
            AppLog.hls("sabr error: fields=\(fields.keys.sorted()) raw=\(text.debugDescription)")
            return SABRError.server("server rejected the request")
        case .reloadPlayerResponse:
            return SABRError.server("player response expired")
        default:
            return nil
        }
    }

    /// A `MEDIA` payload leads with the varint header id its bytes belong to.
    private func store(media payload: Data, headers: [Int: MediaHeader]) -> Bool {
        guard let (id, offset) = Protobuf.readVarint(payload, 0),
              let header = headers[Int(id)] else {
            return false
        }
        let start = payload.startIndex + offset
        guard start < payload.endIndex else {
            return false
        }
        let data = payload[start..<payload.endIndex]
        // Media arrives in several parts per segment; each continues where the
        // previous one stopped, so position by what is already buffered.
        let written = bufferedLength(itag: header.itag, from: header.startRange)
        store(SABRSegment(
            itag: header.itag,
            start: header.startRange + written,
            data: data,
            isInit: header.isInit
        ))
        if !header.isInit {
            advance(
                itag: header.itag,
                sequence: header.sequence,
                bufferedMs: header.bufferedMs
            )
        }
        return true
    }
}
