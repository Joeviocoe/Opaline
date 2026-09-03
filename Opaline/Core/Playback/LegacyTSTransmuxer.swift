import Foundation

#if LEGACY_IOS9
/// Rewrites fragmented-MP4 media as MPEG-TS, so it can be served over HLS.
///
/// **Why this exists.** SABR's sink is an HLS playlist built by `HLSGenerator`,
/// and that playlist is fMP4 — `#EXT-X-VERSION:7` with `#EXT-X-MAP` — which
/// needs iOS 10. TS-segment HLS is supported all the way back, so the fix is to
/// change the container, not the delivery.
///
/// **Why not the progressive remux used for direct URLs.** That works because
/// byte ranges let us fetch every `moof` header cheaply and build one complete
/// `moov` up front. SABR has no byte ranges: it answers with whole segments, so
/// collecting every header means fetching the entire video before playback. And
/// SABR only matters in a world where direct URLs are gone, which is exactly
/// when range requests stop being available. Transmuxing is a streaming
/// transform — each segment converts on its own, as it arrives.
enum LegacyTSTransmuxer {
    static let packetSize = 188
    static let syncByte: UInt8 = 0x47
    /// Fixed PIDs. Any consistent choice works; these are the conventional ones.
    static let pmtPID: UInt16 = 0x1000
    static let videoPID: UInt16 = 0x100
    static let audioPID: UInt16 = 0x101
    /// 90 kHz, the clock every PTS/DTS in MPEG-TS is expressed in.
    static let clock: Double = 90_000

    /// Continuity counters, which the demuxer checks per PID. A counter that
    /// jumps is read as a dropped packet and the stream stutters, so they are
    /// carried across every packet of a segment.
    struct Continuity {
        var pat: UInt8 = 0
        var pmt: UInt8 = 0
        var video: UInt8 = 0
        var audio: UInt8 = 0
    }

    // MARK: - Packets

    /// One 188-byte transport packet.
    ///
    /// `payload` must already fit whatever room the adaptation field leaves;
    /// the caller splits. Stuffing goes in an adaptation field, never at the
    /// end — a demuxer reads the payload to the end of the packet.
    static func packet(
        pid: UInt16,
        payload: Data,
        start: Bool,
        continuity: UInt8,
        pcr: UInt64? = nil
    ) -> Data {
        var out = Data()
        out.append(syncByte)
        // transport_error 0, payload_unit_start, priority 0, then 13-bit PID.
        out.append(UInt8((start ? 0x40 : 0x00) | UInt8((pid >> 8) & 0x1F)))
        out.append(UInt8(pid & 0xFF))

        let needsAdaptation = pcr != nil || payload.count < packetSize - 4
        let control: UInt8 = needsAdaptation ? 0x30 : 0x10
        out.append(control | (continuity & 0x0F))

        if needsAdaptation {
            var adaptation = Data()
            var flags: UInt8 = 0
            if let pcr = pcr {
                flags |= 0x10
                adaptation.append(contentsOf: pcrBytes(pcr))
            }
            // An adaptation field carrying nothing is a single zero length
            // byte -- there is no flags byte. That case is not cosmetic: a
            // 183-byte payload leaves room for the length byte and nothing
            // else, and writing a flags byte anyway pushes the packet to 189
            // bytes, whose tail the truncation below then silently ate.
            if adaptation.isEmpty && payload.count == packetSize - 5 {
                out.append(0x00)
            } else {
                // Length byte + flags byte are the fixed cost of the field.
                let used = 4 + 2 + adaptation.count
                let stuffing = max(0, packetSize - used - payload.count)
                out.append(UInt8(1 + adaptation.count + stuffing))
                out.append(flags)
                out.append(adaptation)
                if stuffing > 0 {
                    out.append(Data(repeating: 0xFF, count: stuffing))
                }
            }
        }
        out.append(payload)
        // A short final packet would desynchronise the stream. Both of these
        // are now unreachable; they stay as a net, but a silent truncation is
        // what hid the 183-byte bug, so an overlong packet says so.
        if out.count < packetSize {
            out.append(Data(repeating: 0xFF, count: packetSize - out.count))
        }
        if out.count > packetSize {
            AppLog.player(
                "ts: packet overlong (\(out.count) bytes, payload"
                    + " \(payload.count)); truncating"
            )
        }
        return out.prefix(packetSize)
    }

    /// PCR is 33 bits of 90 kHz base plus a 9-bit 27 MHz extension.
    private static func pcrBytes(_ value: UInt64) -> [UInt8] {
        let base = value & 0x1_FFFF_FFFF
        return [
            UInt8((base >> 25) & 0xFF),
            UInt8((base >> 17) & 0xFF),
            UInt8((base >> 9) & 0xFF),
            UInt8((base >> 1) & 0xFF),
            UInt8(((base & 0x1) << 7) | 0x7E),
            0x00,
        ]
    }

    // MARK: - Programme tables

    /// Programme Association Table: one programme, pointing at the PMT.
    static func pat(continuity: inout UInt8) -> Data {
        var section = Data()
        section.append(0x00)                    // table_id
        section.append(contentsOf: [0xB0, 0x0D]) // section syntax + length 13
        section.append(contentsOf: [0x00, 0x01]) // transport_stream_id
        section.append(0xC1)                    // version 0, current
        section.append(contentsOf: [0x00, 0x00]) // section number, last
        section.append(contentsOf: [0x00, 0x01]) // programme number 1
        section.append(UInt8(0xE0 | UInt8((pmtPID >> 8) & 0x1F)))
        section.append(UInt8(pmtPID & 0xFF))
        section.append(contentsOf: crc32Bytes(section))
        // A pointer_field of 0 precedes a section at the start of a payload.
        var payload = Data([0x00])
        payload.append(section)
        let out = packet(pid: 0, payload: payload, start: true, continuity: continuity)
        continuity = (continuity &+ 1) & 0x0F
        return out
    }

    /// Programme Map Table: the elementary streams in this programme.
    static func pmt(hasVideo: Bool, hasAudio: Bool, continuity: inout UInt8) -> Data {
        var streams = Data()
        if hasVideo {
            streams.append(0x1B)                // H.264
            streams.append(UInt8(0xE0 | UInt8((videoPID >> 8) & 0x1F)))
            streams.append(UInt8(videoPID & 0xFF))
            streams.append(contentsOf: [0xF0, 0x00])
        }
        if hasAudio {
            streams.append(0x0F)                // AAC in ADTS
            streams.append(UInt8(0xE0 | UInt8((audioPID >> 8) & 0x1F)))
            streams.append(UInt8(audioPID & 0xFF))
            streams.append(contentsOf: [0xF0, 0x00])
        }
        let pcrPID = hasVideo ? videoPID : audioPID
        var section = Data()
        section.append(0x02)                    // table_id
        let length = 13 + streams.count
        section.append(UInt8(0xB0 | UInt8((length >> 8) & 0x0F)))
        section.append(UInt8(length & 0xFF))
        section.append(contentsOf: [0x00, 0x01]) // programme number
        section.append(0xC1)
        section.append(contentsOf: [0x00, 0x00])
        section.append(UInt8(0xE0 | UInt8((pcrPID >> 8) & 0x1F)))
        section.append(UInt8(pcrPID & 0xFF))
        section.append(contentsOf: [0xF0, 0x00]) // programme_info_length
        section.append(streams)
        section.append(contentsOf: crc32Bytes(section))
        var payload = Data([0x00])
        payload.append(section)
        let out = packet(pid: pmtPID, payload: payload, start: true, continuity: continuity)
        continuity = (continuity &+ 1) & 0x0F
        return out
    }

    // MARK: - PES

    /// Wraps one access unit in a PES packet.
    ///
    /// `length` is left at 0 for video: a frame routinely exceeds the 16-bit
    /// field, and 0 means "unbounded" — legal for video, not for audio.
    static func pes(
        streamID: UInt8,
        payload: Data,
        pts: UInt64,
        dts: UInt64?,
        unbounded: Bool
    ) -> Data {
        var header = Data()
        header.append(contentsOf: [0x00, 0x00, 0x01, streamID])
        // Flags: '10' marker, then PTS(+DTS) present.
        let hasDTS = dts != nil && dts != pts
        let stampBytes = hasDTS ? 10 : 5
        let bodyLength = unbounded ? 0 : min(payload.count + 3 + stampBytes, 0xFFFF)
        header.append(UInt8((bodyLength >> 8) & 0xFF))
        header.append(UInt8(bodyLength & 0xFF))
        header.append(0x80)                                  // marker, no scrambling
        header.append(hasDTS ? 0xC0 : 0x80)                  // PTS / PTS+DTS flags
        header.append(UInt8(stampBytes))
        header.append(contentsOf: timestamp(pts, prefix: hasDTS ? 0x30 : 0x20))
        if hasDTS, let dts = dts {
            header.append(contentsOf: timestamp(dts, prefix: 0x10))
        }
        var out = header
        out.append(payload)
        return out
    }

    /// A 33-bit timestamp in the 5-byte marker-interleaved PES form.
    private static func timestamp(_ value: UInt64, prefix: UInt8) -> [UInt8] {
        let v = value & 0x1_FFFF_FFFF
        return [
            prefix | UInt8((v >> 29) & 0x0E) | 0x01,
            UInt8((v >> 22) & 0xFF),
            UInt8(((v >> 14) & 0xFE) | 0x01),
            UInt8((v >> 7) & 0xFF),
            UInt8(((v << 1) & 0xFE) | 0x01),
        ]
    }

    /// Splits a PES packet across transport packets on one PID.
    static func packetize(
        _ pes: Data,
        pid: UInt16,
        continuity: inout UInt8,
        pcr: UInt64?
    ) -> Data {
        var out = Data()
        var offset = 0
        var first = true
        while offset < pes.count {
            // The first packet carries the PCR, and its adaptation field eats
            // into the payload — so the room available differs from the rest.
            let overhead = first && pcr != nil ? 4 + 8 : 4
            let room = packetSize - overhead
            let take = min(room, pes.count - offset)
            let chunk = pes.subdata(in: offset..<(offset + take))
            out.append(packet(
                pid: pid,
                payload: chunk,
                start: first,
                continuity: continuity,
                pcr: first ? pcr : nil
            ))
            continuity = (continuity &+ 1) & 0x0F
            offset += take
            first = false
        }
        return out
    }

    // MARK: - Elementary stream framing

    /// AVCC (4-byte length prefixes) to Annex B (start codes).
    ///
    /// TS carries H.264 in Annex B; MP4 stores it length-prefixed. Feeding one
    /// to a demuxer expecting the other yields a stream that parses to nothing.
    static func annexB(fromAVCC sample: Data, nalLengthSize: Int) -> Data {
        var out = Data()
        var index = sample.startIndex
        while index + nalLengthSize <= sample.endIndex {
            var length = 0
            for offset in 0..<nalLengthSize {
                length = (length << 8) | Int(sample[index + offset])
            }
            index += nalLengthSize
            guard length > 0, index + length <= sample.endIndex else {
                break
            }
            out.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            out.append(sample.subdata(in: index..<(index + length)))
            index += length
        }
        return out
    }

    /// An ADTS header for one AAC frame.
    ///
    /// TS carries AAC as ADTS; MP4 stores raw frames with the configuration in
    /// `esds`. Without a header per frame the demuxer finds no syncword.
    static func adts(
        frameLength: Int,
        objectType: Int,
        sampleRateIndex: Int,
        channels: Int
    ) -> Data {
        // Each field is narrowed to UInt8 on its own line. Swift 5.4 could not
        // type-check the combined expression in reasonable time, and mixing Int
        // and UInt8 mid-expression is how the third of these bytes ended up
        // ambiguous.
        let total = frameLength + 7
        let profile = UInt8((objectType - 1) & 0x03)
        let rateIndex = UInt8(sampleRateIndex & 0x0F)
        let channelCount = UInt8(channels & 0x07)
        let byte2: UInt8 = (profile << 6) | (rateIndex << 2) | ((channelCount >> 2) & 0x01)
        let byte3: UInt8 = ((channelCount & 0x03) << 6) | UInt8((total >> 11) & 0x03)
        let byte4 = UInt8((total >> 3) & 0xFF)
        let byte5: UInt8 = UInt8((total & 0x07) << 5) | 0x1F

        var out = Data()
        out.append(0xFF)
        out.append(0xF1)                                  // MPEG-4, no CRC
        out.append(byte2)
        out.append(byte3)
        out.append(byte4)
        out.append(byte5)
        out.append(0xFC)
        return out
    }

    // MARK: - Codec configuration

    /// SPS and PPS from the `avcC` box in the init segment's sample entry.
    ///
    /// TS has no place to carry them out of band, so they are prepended to every
    /// keyframe as Annex B. A stream missing them decodes nothing at all — the
    /// decoder never learns the resolution or profile.
    struct AVCConfig {
        let sps: [Data]
        let pps: [Data]
        /// NAL length prefix size, from `avcC`. Usually 4, occasionally 2.
        let nalLengthSize: Int

        /// The parameter sets as an Annex B prelude.
        var prelude: Data {
            var out = Data()
            for set in sps + pps {
                out.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                out.append(set)
            }
            return out
        }
    }

    static func avcConfig(fromInit data: Data) -> AVCConfig? {
        // stsd -> avc1 -> avcC. The sample entry has a fixed 78-byte preamble
        // before its child boxes.
        guard let stsd = MP4Box.find("moov/trak/mdia/minf/stbl/stsd", in: data) else {
            return nil
        }
        let entries = MP4Box.children(
            of: data, from: stsd.payloadStart + 8, to: stsd.payloadEnd
        )
        guard let entry = entries.first(where: { $0.type == "avc1" || $0.type == "avc3" }),
              let avcC = MP4Box.find(
                  "avcC", in: data, from: entry.payloadStart + 78, to: entry.payloadEnd
              ) else {
            return nil
        }
        let base = data.startIndex
        var cursor = avcC.payloadStart
        guard cursor + 6 <= data.count else {
            return nil
        }
        let nalLengthSize = Int(data[base + cursor + 4] & 0x03) + 1
        let spsCount = Int(data[base + cursor + 5] & 0x1F)
        cursor += 6

        /// Each parameter set is a 16-bit length followed by its bytes.
        func readSets(_ count: Int) -> [Data]? {
            var sets: [Data] = []
            for _ in 0..<count {
                guard cursor + 2 <= data.count else { return nil }
                let size = Int(data[base + cursor]) << 8 | Int(data[base + cursor + 1])
                cursor += 2
                guard size > 0, cursor + size <= data.count else { return nil }
                sets.append(data.subdata(in: (base + cursor)..<(base + cursor + size)))
                cursor += size
            }
            return sets
        }

        guard let sps = readSets(spsCount), cursor < data.count else {
            return nil
        }
        let ppsCount = Int(data[base + cursor])
        cursor += 1
        guard let pps = readSets(ppsCount) else {
            return nil
        }
        return AVCConfig(sps: sps, pps: pps, nalLengthSize: nalLengthSize)
    }

    /// AAC parameters from the `esds` box, for the ADTS header on every frame.
    ///
    /// TS carries no out-of-band audio config, so each frame gets a 7-byte ADTS
    /// header built from these three fields. Getting the rate index wrong does
    /// not fail loudly -- audio plays at the wrong speed and drifts from video.
    struct AACConfig {
        let objectType: Int
        let rateIndex: Int
        let channels: Int
    }

    /// Sampling frequencies in AudioSpecificConfig index order.
    static let aacRates: [Int] = [
        96000, 88200, 64000, 48000, 44100, 32000,
        24000, 22050, 16000, 12000, 11025, 8000, 7350,
    ]

    static func aacConfig(fromInit data: Data) -> AACConfig? {
        guard let stsd = MP4Box.find("moov/trak/mdia/minf/stbl/stsd", in: data) else {
            return nil
        }
        let entries = MP4Box.children(
            of: data, from: stsd.payloadStart + 8, to: stsd.payloadEnd
        )
        guard let entry = entries.first(where: { $0.type == "mp4a" }) else {
            return nil
        }
        let base = data.startIndex

        /// The audio sample entry's own fields, used as the fallback when the
        /// descriptor chain cannot be walked. `samplerate` is 16.16 fixed point
        /// and the integer half is the only part that matters here.
        func fromSampleEntry() -> AACConfig? {
            let p = entry.payloadStart
            guard p + 28 <= data.count else { return nil }
            let channels = Int(data[base + p + 16]) << 8 | Int(data[base + p + 17])
            let rate = Int(data[base + p + 24]) << 8 | Int(data[base + p + 25])
            guard let idx = aacRates.firstIndex(of: rate), channels > 0 else {
                return nil
            }
            // Object type 2 is AAC-LC, which is all YouTube serves in mp4a.
            return AACConfig(objectType: 2, rateIndex: idx, channels: channels)
        }

        // An AudioSampleEntry has a 28-byte preamble before its child boxes,
        // where a visual entry has 78.
        guard let esds = MP4Box.find(
            "esds", in: data, from: entry.payloadStart + 28, to: entry.payloadEnd
        ) else {
            return fromSampleEntry()
        }

        // esds is a full box: 1 version byte plus 3 flag bytes, then the
        // ES_Descriptor chain.
        var cursor = esds.payloadStart + 4

        /// Descriptor lengths are 7 bits per byte, high bit meaning "continues".
        /// A malformed length here would otherwise walk off the end.
        func readLength() -> Int? {
            var value = 0
            for _ in 0..<4 {
                guard cursor < data.count else { return nil }
                let byte = data[base + cursor]
                cursor += 1
                value = (value << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { return value }
            }
            return nil
        }

        /// Advances past the header of the descriptor with `tag`, or fails.
        func enter(tag: UInt8) -> Bool {
            guard cursor < data.count, data[base + cursor] == tag else { return false }
            cursor += 1
            return readLength() != nil
        }

        guard enter(tag: 0x03), cursor + 3 <= data.count else {
            return fromSampleEntry()
        }
        let flags = data[base + cursor + 2]
        cursor += 3
        if flags & 0x80 != 0 { cursor += 2 }          // stream dependence
        if flags & 0x40 != 0 {                        // URL, a length-prefixed string
            guard cursor < data.count else { return fromSampleEntry() }
            cursor += 1 + Int(data[base + cursor])
        }
        if flags & 0x20 != 0 { cursor += 2 }          // OCR stream

        // DecoderConfigDescriptor: 13 fixed bytes, then DecoderSpecificInfo.
        guard enter(tag: 0x04) else { return fromSampleEntry() }
        cursor += 13
        guard enter(tag: 0x05), cursor + 2 <= data.count else {
            return fromSampleEntry()
        }

        // AudioSpecificConfig: 5 bits object type, 4 bits rate index,
        // 4 bits channel configuration.
        let b0 = Int(data[base + cursor])
        let b1 = Int(data[base + cursor + 1])
        let objectType = b0 >> 3
        let rateIndex = ((b0 & 0x07) << 1) | (b1 >> 7)
        let channels = (b1 >> 3) & 0x0F

        // Escape values need bits this parser does not read: object type 31
        // means a 6-bit extension, rate index 15 an inline 24-bit frequency.
        // Neither appears in YouTube's AAC-LC, so fall back rather than guess.
        guard objectType > 0, objectType < 31,
              rateIndex < aacRates.count,
              channels > 0, channels <= 7 else {
            return fromSampleEntry()
        }
        return AACConfig(
            objectType: objectType, rateIndex: rateIndex, channels: channels
        )
    }

    // MARK: - Segment assembly

    /// What a track needs before any of its fragments can be transmuxed.
    struct TrackSetup {
        let isVideo: Bool
        /// Media timescale, for converting `trun` durations to the 90 kHz clock.
        let timescale: UInt32
        let avc: AVCConfig?
        /// AAC parameters, when this is an audio track.
        let aacObjectType: Int
        let aacRateIndex: Int
        let aacChannels: Int
    }

    /// Converts one fragmented-MP4 segment into a TS segment.
    ///
    /// Timestamps are the part that goes wrong quietly: they must be on the
    /// 90 kHz clock, DTS must be monotonic, and PTS must carry the composition
    /// offset or B-frames present out of order — the same defect that made the
    /// progressive remux jitter until `ctts` was added.
    ///
    /// Returns nil rather than a partial segment: a short TS segment plays and
    /// then desynchronises, which is far harder to diagnose than a refusal.
    static func segment(
        fragment: Data,
        moofAt origin: Int64,
        setup: TrackSetup,
        baseMediaTime: UInt64
    ) -> Data? {
        let samples = LegacyProgressiveRemux.parseFragment(fragment, moofAt: origin)
        guard !samples.isEmpty else {
            AppLog.player("ts: no samples in fragment at \(origin)")
            return nil
        }
        // Sample bytes live in this fragment's own mdat; `originOffset` is a
        // whole-stream offset, so rebase it onto the buffer in hand.
        guard let moof = MP4Box.header(in: fragment, at: 0),
              let mdat = MP4Box.header(in: fragment, at: moof.next),
              mdat.type == "mdat" else {
            AppLog.player("ts: fragment at \(origin) has no mdat")
            return nil
        }
        let mdatOrigin = origin + Int64(mdat.payloadStart)

        var continuity = Continuity()
        var out = Data()
        out.append(pat(continuity: &continuity.pat))
        out.append(pmt(
            hasVideo: setup.isVideo,
            hasAudio: !setup.isVideo,
            continuity: &continuity.pmt
        ))

        let pid = setup.isVideo ? videoPID : audioPID
        let streamID: UInt8 = setup.isVideo ? 0xE0 : 0xC0
        var decodeTime = baseMediaTime
        var first = true

        for sample in samples {
            // `originOffset` is a whole-stream offset; rebase it onto this
            // buffer, whose mdat payload begins at `mdat.payloadStart`.
            let offset = fragment.startIndex + mdat.payloadStart
                + Int(sample.originOffset - mdatOrigin)
            guard offset >= fragment.startIndex,
                  offset + Int(sample.size) <= fragment.endIndex else {
                AppLog.player("ts: sample runs outside the fragment; segment refused")
                return nil
            }
            let raw = fragment.subdata(in: offset..<(offset + Int(sample.size)))

            // 90 kHz from the track's own timescale.
            let dts = decodeTime * UInt64(clock) / UInt64(setup.timescale)
            let ptsTicks = Int64(decodeTime) + Int64(sample.compositionOffset)
            let pts = UInt64(max(0, ptsTicks)) * UInt64(clock) / UInt64(setup.timescale)

            var payload = Data()
            if setup.isVideo, let avc = setup.avc {
                // Parameter sets ride with every keyframe: a TS stream has no
                // out-of-band place for them, and a viewer joining mid-stream
                // (or a decoder reset) needs them to decode anything.
                // AUD first, then parameter sets, then the slices.
                payload.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x09, 0xF0])
                if sample.isSync {
                    payload.append(avc.prelude)
                }
                payload.append(annexB(fromAVCC: raw, nalLengthSize: avc.nalLengthSize))
            } else if !setup.isVideo {
                payload.append(adts(
                    frameLength: raw.count,
                    objectType: setup.aacObjectType,
                    sampleRateIndex: setup.aacRateIndex,
                    channels: setup.aacChannels
                ))
                payload.append(raw)
            } else {
                AppLog.player("ts: video track without avcC; segment refused")
                return nil
            }

            let packet = pes(
                streamID: streamID,
                payload: payload,
                pts: pts,
                dts: setup.isVideo ? dts : nil,
                unbounded: setup.isVideo
            )
            // Swift has no ternary over `inout`, and the counter must be the
            // one for this PID or the demuxer reads dropped packets.
            if setup.isVideo {
                out.append(packetize(
                    packet, pid: pid, continuity: &continuity.video,
                    pcr: first ? dts : nil
                ))
            } else {
                out.append(packetize(
                    packet, pid: pid, continuity: &continuity.audio,
                    pcr: first ? dts : nil
                ))
            }
            first = false
            decodeTime += UInt64(sample.duration)
        }

        AppLog.player(
            "ts: \(samples.count) samples -> \(out.count / packetSize) packets"
                + " (\(out.count / 1024) KB) for \(setup.isVideo ? "video" : "audio")"
        )
        return out
    }

    /// MPEG-2 systems CRC-32, big-endian, as the section tables require.
    static func crc32Bytes(_ data: Data) -> [UInt8] {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                crc = (crc & 0x8000_0000) != 0
                    ? (crc << 1) ^ 0x04C1_1DB7
                    : crc << 1
            }
        }
        return [
            UInt8((crc >> 24) & 0xFF), UInt8((crc >> 16) & 0xFF),
            UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF),
        ]
    }
}
#endif
