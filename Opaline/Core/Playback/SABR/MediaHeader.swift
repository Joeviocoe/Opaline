import Foundation

/// `MEDIA_HEADER` — what the `MEDIA` parts after it belong to.
///
/// Fields are `MediaHeader` in googlevideo's protos: 3 itag, 6 start_range,
/// 8 is_init_seg, 9 sequence_number, 11 start_ms, 12 duration_ms, 15 a
/// `TimeRange` of start, duration and timescale.
struct MediaHeader {
    let itag: Int
    let startRange: Int64
    let sequence: Int
    let isInit: Bool
    let startMs: Int
    let durationMs: Int
    let timescale: Int

    init?(_ payload: Data) {
        let fields = Protobuf.parse(payload)
        guard let itag = fields.number(3) else {
            return nil
        }
        self.itag = itag
        startRange = Int64(fields.number(6) ?? 0)
        sequence = fields.number(9) ?? 0
        isInit = (fields.number(8) ?? 0) != 0
        let time = fields.data(15).map(Protobuf.parse)
        timescale = time?.number(3) ?? 1_000
        // The plain millisecond fields where the server sends them, the tick
        // range where it does not.
        startMs = fields.number(11) ?? Self.ms(time?.number(1), timescale)
        durationMs = fields.number(12) ?? Self.ms(time?.number(2), timescale)
    }

    private static func ms(_ ticks: Int?, _ timescale: Int) -> Int {
        guard let ticks, timescale > 0 else {
            return 0
        }
        return ticks * 1_000 / timescale
    }
}

enum SABRError: LocalizedError {
    case noInitSegment
    case stalled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noInitSegment:
            "SABR returned no init segment"
        case .stalled:
            "SABR returned no media"
        case .server(let detail):
            "SABR error: \(detail)"
        }
    }
}
