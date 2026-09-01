import Foundation

/// `MEDIA_HEADER` — what the `MEDIA` parts after it belong to.
///
/// Fields are `MediaHeader` in googlevideo's protos: 3 itag, 5 xtags,
/// 6 start_range, 8 is_init_seg, 9 sequence_number, 11 start_ms,
/// 12 duration_ms, 13 a `FormatId`, 15 a `TimeRange` of start, duration and
/// timescale.
struct MediaHeader {
    let itag: Int
    /// What the server says it is serving — the only way to tell a dubbed
    /// track from the original, since both carry the same itag.
    let xtags: String?
    let startRange: Int64
    let sequence: Int
    let isInit: Bool
    let startMs: Int
    let durationMs: Int
    let timescale: Int

    init?(_ payload: Data) {
        let fields = Protobuf.parse(payload)
        guard let itagField = fields.number(3) else {
            return nil
        }
        self.itag = Int(clamping: itagField)
        let formatId = fields.data(13).map(Protobuf.parse)
        xtags = fields.string(5)
            ?? formatId?.string(3)
        startRange = fields.number(6) ?? 0
        sequence = Int(clamping: fields.number(9) ?? 0)
        isInit = (fields.number(8) ?? 0) != 0
        let time = fields.data(15).map(Protobuf.parse)
        let scale = Int(clamping: time?.number(3) ?? 1_000)
        timescale = scale
        // The plain millisecond fields where the server sends them, the tick
        // range where it does not.
        //
        // Computed into locals first: Swift 5.4's definite-initialization pass
        // rejects a closure in the same expression that initialises a stored
        // constant ("captured by a closure before being initialized"), even
        // though the closure captures nothing. Later compilers accept the
        // direct form, so this is shape, not meaning.
        let explicitStart = fields.number(11).map { Int(clamping: $0) }
        let explicitDuration = fields.number(12).map { Int(clamping: $0) }
        startMs = explicitStart ?? Self.ms(time?.number(1), scale)
        durationMs = explicitDuration ?? Self.ms(time?.number(2), scale)
    }

    /// Ticks come off the wire, so scale in 64-bit and clamp: `ticks * 1_000`
    /// overflows a 32-bit Int well inside the plausible range.
    private static func ms(_ ticks: Int64?, _ timescale: Int) -> Int {
        guard let ticks = ticks, timescale > 0 else {
            return 0
        }
        let scaled = ticks.multipliedReportingOverflow(by: 1_000)
        guard !scaled.overflow else {
            return 0
        }
        return Int(clamping: scaled.partialValue / Int64(timescale))
    }
}

enum SABRError: LocalizedError {
    case noInitSegment
    case stalled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noInitSegment:
            return "SABR returned no init segment"
        case .stalled:
            return "SABR returned no media"
        case .server(let detail):
            return "SABR error: \(detail)"
        }
    }
}
