import Foundation

#if LEGACY_IOS9
/// Rewrites one fragmented MP4 stream as a progressive one.
///
/// The fragmented form makes AVFoundation walk every `moof` to learn the
/// timing — 40 MB read and still unfinished, ~30 s to smooth playback on an
/// iPad 3. A progressive file states it once, in a `moov` at the front, so the
/// player reads an index and then streams.
///
/// Nothing here is downloaded specially: the init segment, the `sidx` and the
/// `moof` headers are what index priming already fetches in a few seconds.
enum LegacyProgressiveRemux {
    /// One sample, as `trun` describes it.
    struct Sample {
        let size: UInt32
        let duration: UInt32
        /// Presentation time minus decode time, in media ticks.
        ///
        /// H.264 with B-frames does not present frames in the order it decodes
        /// them. Dropping this offset makes presentation time equal decode time,
        /// so frames appear out of order — which looks like jitter, and only in
        /// video, because audio is never reordered. That is precisely the
        /// symptom it produced on the device.
        let compositionOffset: Int32
        let isSync: Bool
        /// Where the bytes live in the ORIGINAL stream.
        let originOffset: Int64
    }

    /// What the init segment tells us about the track.
    struct TrackConfig {
        let trackID: UInt32
        let timescale: UInt32
        /// The `stsd` box, reused verbatim: it carries the avc1/mp4a sample
        /// entry with its codec configuration, which we have no reason to
        /// rebuild and every reason not to.
        let sampleDescription: Data
        let handler: String
        let width: UInt32
        let height: UInt32
    }

    /// A finished progressive file: a header to serve directly, and a map from
    /// the file's own offsets back to ranges of the original stream.
    struct Remuxed {
        let header: Data
        /// `mdat` payload, in order, as ranges of the original stream.
        let mediaRanges: [(origin: Int64, length: Int64)]
        let totalLength: Int64

        /// Where a byte of the virtual file comes from.
        enum Source {
            case header(Data)
            case origin(offset: Int64, length: Int64)
        }
    }

    // MARK: - Init segment

    /// Reads the track's configuration out of the init segment's `moov`.
    static func parseInit(_ data: Data) -> TrackConfig? {
        let base = data.startIndex
        guard let mdhd = MP4Box.find("moov/trak/mdia/mdhd", in: data),
              let hdlr = MP4Box.find("moov/trak/mdia/hdlr", in: data),
              let stsd = MP4Box.find("moov/trak/mdia/minf/stbl/stsd", in: data),
              let tkhd = MP4Box.find("moov/trak/tkhd", in: data) else {
            return nil
        }
        guard base + mdhd.payloadStart < data.endIndex,
              base + tkhd.payloadStart < data.endIndex else {
            return nil
        }
        let version = data[base + mdhd.payloadStart]
        // v0 puts creation/modification in 32 bits, v1 in 64: the timescale sits
        // after them either way, and reading the wrong one yields a nonsense
        // timescale and a file that plays at the wrong speed.
        let timescaleOffset = mdhd.payloadStart + (version == 1 ? 4 + 16 : 4 + 8)
        guard let timescale = MP4Box.be32(data, base + timescaleOffset) else {
            AppLog.player("remux: mdhd timescale is outside the init segment")
            return nil
        }

        let tkhdVersion = data[base + tkhd.payloadStart]
        let trackIDOffset = tkhd.payloadStart + (tkhdVersion == 1 ? 4 + 16 : 4 + 8)
        guard let trackID = MP4Box.be32(data, base + trackIDOffset),
              // width/height are 16.16 fixed point at the end of tkhd.
              let rawWidth = MP4Box.be32(data, base + tkhd.payloadEnd - 8),
              let rawHeight = MP4Box.be32(data, base + tkhd.payloadEnd - 4),
              let handler = MP4Box.ascii(data, base + hdlr.payloadStart + 8, length: 4) else {
            AppLog.player("remux: tkhd/hdlr fields are outside the init segment")
            return nil
        }
        let width = rawWidth >> 16
        let height = rawHeight >> 16

        return TrackConfig(
            trackID: trackID == 0 ? 1 : trackID,
            timescale: timescale == 0 ? 1_000 : timescale,
            sampleDescription: data.subdata(
                in: (base + stsd.payloadStart - 8)..<(base + stsd.payloadEnd)
            ),
            handler: handler,
            width: width,
            height: height
        )
    }

    // MARK: - Fragments

    /// Samples described by one fragment's `trun`, with their positions in the
    /// original stream.
    ///
    /// `base_data_offset` is deliberately ignored: YouTube's fragments use the
    /// default-base-is-moof form, so media begins at the `mdat` payload that
    /// follows this `moof` — which is what `mdatOrigin` carries.
    static func parseFragment(_ data: Data, moofAt moofOrigin: Int64) -> [Sample] {
        let base = data.startIndex
        // Say what was actually found when this is not a fragment. A wrong base
        // offset produces a perfectly valid box of some other type, and without
        // naming it the failure is just "0 fragments parsed" with no clue why —
        // which is exactly how a media-relative sidx offset cost a round.
        guard let moof = MP4Box.header(in: data, at: 0) else {
            AppLog.player(
                "remux: no readable box at offset \(moofOrigin)"
                    + " in \(data.count) B — wrong offset?"
            )
            return []
        }
        guard moof.type == "moof" else {
            AppLog.player(
                "remux: expected 'moof' at \(moofOrigin), found '\(moof.type)'"
                    + " (size \(moof.next)) — offset base is wrong"
            )
            return []
        }
        guard
              let traf = MP4Box.find("traf", in: data, from: moof.payloadStart, to: moof.payloadEnd),
              let trun = MP4Box.find("trun", in: data, from: traf.payloadStart, to: traf.payloadEnd)
        else {
            AppLog.player("remux: moof at \(moofOrigin) has no traf/trun")
            return []
        }

        // Defaults from tfhd, used when trun omits per-sample values.
        var defaultDuration: UInt32 = 0
        var defaultSize: UInt32 = 0
        /// `default_sample_flags`. Nil when tfhd omits it, which is the only
        /// case where a sample carries no sync information at all.
        var defaultFlags: UInt32?
        if let tfhd = MP4Box.find("tfhd", in: data, from: traf.payloadStart, to: traf.payloadEnd),
           let rawFlags = MP4Box.be32(data, base + tfhd.payloadStart) {
            let flags = rawFlags & 0x00FF_FFFF
            var cursor = tfhd.payloadStart + 4 + 4 // version/flags + track_ID
            if flags & 0x01 != 0 { cursor += 8 }   // base_data_offset
            if flags & 0x02 != 0 { cursor += 4 }   // sample_description_index
            if flags & 0x08 != 0 {
                defaultDuration = MP4Box.be32(data, base + cursor) ?? 0
                cursor += 4
            }
            if flags & 0x10 != 0 {
                defaultSize = MP4Box.be32(data, base + cursor) ?? 0
                cursor += 4
            }
            if flags & 0x20 != 0 {
                defaultFlags = MP4Box.be32(data, base + cursor)
                cursor += 4
            }
        }

        guard base + trun.payloadStart < data.endIndex,
              let rawTrunFlags = MP4Box.be32(data, base + trun.payloadStart),
              let rawCount = MP4Box.be32(data, base + trun.payloadStart + 4) else {
            return []
        }
        let trunFlags = rawTrunFlags & 0x00FF_FFFF
        // trun version 0 stores composition offsets unsigned, version 1 signed.
        // Reading a signed offset as unsigned turns a small negative into a
        // huge positive and throws the whole presentation timeline out.
        let trunVersion = data[base + trun.payloadStart - 4 + 0]
        // Sample counts come off the wire. A huge one would allocate wildly
        // before the truncation check could fire, and on a 1 GB device that is
        // a jetsam rather than a parse failure.
        guard rawCount <= 100_000 else {
            AppLog.player("remux: implausible trun sample count \(rawCount); fragment skipped")
            return []
        }
        let count = Int(rawCount)
        var cursor = trun.payloadStart + 8
        if trunFlags & 0x0001 != 0 { cursor += 4 } // data_offset
        // first_sample_flags. Skipping this was a real bug: YouTube marks the
        // opening keyframe of every fragment here and nowhere else, so
        // discarding it left the whole fragment looking like keyframes.
        var firstSampleFlags: UInt32?
        if trunFlags & 0x0004 != 0 {
            firstSampleFlags = MP4Box.be32(data, base + cursor)
            cursor += 4
        }

        // Media follows the moof box.
        var mediaCursor = moofOrigin + Int64(moof.next)
        // Step over the mdat header to reach its payload.
        if let mdat = MP4Box.header(in: data, at: moof.next), mdat.type == "mdat" {
            mediaCursor = moofOrigin + Int64(mdat.payloadStart)
        } else {
            mediaCursor += 8
        }

        var samples: [Sample] = []
        samples.reserveCapacity(count)
        var truncated = false
        for index in 0..<count {
            var duration = defaultDuration
            var size = defaultSize
            // Precedence per ISO/IEC 14496-12: per-sample flags, else
            // first_sample_flags for sample 0, else the tfhd default.
            var flags: UInt32 = (index == 0 ? firstSampleFlags : nil)
                ?? defaultFlags ?? 0
            if trunFlags & 0x0100 != 0 {
                guard let value = MP4Box.be32(data, base + cursor) else {
                    truncated = true
                    break
                }
                duration = value
                cursor += 4
            }
            if trunFlags & 0x0200 != 0 {
                guard let value = MP4Box.be32(data, base + cursor) else {
                    truncated = true
                    break
                }
                size = value
                cursor += 4
            }
            if trunFlags & 0x0400 != 0 {
                guard let value = MP4Box.be32(data, base + cursor) else {
                    truncated = true
                    break
                }
                flags = value
                cursor += 4
            }
            var compositionOffset: Int32 = 0
            if trunFlags & 0x0800 != 0 {
                guard let raw = MP4Box.be32(data, base + cursor) else {
                    truncated = true
                    break
                }
                compositionOffset = trunVersion == 0
                    ? Int32(truncatingIfNeeded: raw)
                    : Int32(bitPattern: raw)
                cursor += 4
            }
            // sample_is_non_sync_sample lives in bit 16 of the sample flags.
            let nonSync = (flags & 0x0001_0000) != 0
            // With no per-sample flags, no first_sample_flags and no tfhd
            // default, nothing in the fragment states sync at all; the opening
            // sample is the only safe assumption.
            let undeclared = trunFlags & 0x0400 == 0
                && firstSampleFlags == nil && defaultFlags == nil
            samples.append(Sample(
                size: size,
                duration: duration,
                compositionOffset: compositionOffset,
                isSync: undeclared ? index == 0 : !nonSync,
                originOffset: mediaCursor
            ))
            mediaCursor += Int64(size)
        }
        if truncated {
            // The fetched head did not contain the whole trun. Returning a short
            // list would silently lose the tail of the fragment, so report
            // nothing and let the validator refuse the remux.
            AppLog.player(
                "remux: trun truncated at \(samples.count)/\(count) samples"
                    + " in the \(data.count) B fetched for offset \(moofOrigin)"
                    + " — raise the primed head size"
            )
            return []
        }
        return samples
    }

    // MARK: - Building the progressive file

    /// Assembles `ftyp` + `moov` + `mdat` header, and the map back to the
    /// original stream's bytes.
    ///
    /// The sample data itself is never copied: `mdat` is served by proxying the
    /// original fragments' payloads in order, which is why this costs a few
    /// hundred KB of headers rather than the size of the video.
    static func build(
        config: TrackConfig,
        samples: [Sample],
        label: String,
        expectedDurationMs: Int?,
        originLength: Int64,
        fragmentsSeen: Int,
        fragmentsExpected: Int
    ) -> Remuxed? {
        guard validate(
            config: config,
            samples: samples,
            label: label,
            expectedDurationMs: expectedDurationMs,
            originLength: originLength,
            fragmentsSeen: fragmentsSeen,
            fragmentsExpected: fragmentsExpected
        ) else {
            return nil
        }
        let mediaLength = samples.reduce(Int64(0)) { $0 + Int64($1.size) }
        let totalDuration = samples.reduce(UInt64(0)) { $0 + UInt64($1.duration) }

        // Built first with a placeholder mdat start, then again once the header
        // size is known: chunk offsets in `stco` are absolute within the file,
        // so they depend on how long the header turns out to be.
        var mdatStart = 0
        var header = Data()
        for _ in 0..<2 {
            var moov = Data()
            moov.append(mvhd(timescale: config.timescale, duration: totalDuration))
            moov.append(trak(
                config: config,
                samples: samples,
                duration: totalDuration,
                mdatStart: Int64(mdatStart)
            ))
            let moovBox = MP4Box.box("moov", moov)
            var out = Data()
            out.append(ftyp())
            out.append(moovBox)
            // 64-bit mdat: a 78 MB video is fine in 32 bits, but the largesize
            // form costs 8 bytes and removes the question entirely.
            out.append(MP4Box.u32(1))
            out.append(contentsOf: Array("mdat".utf8))
            let length = UInt64(mediaLength + 16)
            var big = Data()
            for shift in stride(from: 56, through: 0, by: -8) {
                big.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
            out.append(big)
            _ = length
            header = out
            mdatStart = out.count
        }

        var ranges: [(origin: Int64, length: Int64)] = []
        // Contiguous samples share a range: YouTube's fragments are laid out in
        // order, so this collapses thousands of samples into a few hundred.
        for sample in samples {
            if let last = ranges.last, last.origin + last.length == sample.originOffset {
                ranges[ranges.count - 1].length += Int64(sample.size)
            } else {
                ranges.append((origin: sample.originOffset, length: Int64(sample.size)))
            }
        }

        AppLog.player(
            "remux: built \(header.count / 1024) KB header,"
                + " \(ranges.count) contiguous media ranges from \(samples.count) samples,"
                + " mdat starts at \(mdatStart)"
        )
        return Remuxed(
            header: header,
            mediaRanges: ranges,
            totalLength: Int64(header.count) + mediaLength
        )
    }

    /// Checks the rebuilt index against everything already known to be true.
    ///
    /// A wrong box does not crash: it produces a file that plays at the wrong
    /// speed, plays silently, or refuses to open — all of which look identical
    /// from a device and cost a build cycle each to distinguish. Every invariant
    /// here is checked against a number obtained independently of the remux, and
    /// a failure means falling back to serving the stream raw, which is slow but
    /// known to work.
    private static func validate(
        config: TrackConfig,
        samples: [Sample],
        label: String,
        expectedDurationMs: Int?,
        originLength: Int64,
        fragmentsSeen: Int,
        fragmentsExpected: Int
    ) -> Bool {
        func reject(_ why: String) -> Bool {
            AppLog.player("remux[\(label)]: REJECTED — \(why); serving raw instead")
            return false
        }

        guard !samples.isEmpty else {
            return reject("no samples parsed from \(fragmentsSeen) fragments")
        }
        // A fragment that failed to parse leaves a hole in the timeline, and the
        // file would play up to the hole and then misbehave.
        if fragmentsSeen < fragmentsExpected {
            return reject(
                "only \(fragmentsSeen) of \(fragmentsExpected) fragments parsed"
            )
        }
        guard config.timescale > 0 else {
            return reject("timescale is zero")
        }
        guard config.sampleDescription.count > 8 else {
            return reject("empty sample description (no codec config)")
        }
        guard config.handler == "vide" || config.handler == "soun" else {
            return reject("unexpected handler '\(config.handler)'")
        }

        let zeroSized = samples.filter { $0.size == 0 }.count
        let zeroDuration = samples.filter { $0.duration == 0 }.count
        if zeroSized > 0 {
            return reject("\(zeroSized) samples have zero size")
        }
        if zeroDuration > samples.count / 2 {
            return reject("\(zeroDuration) of \(samples.count) samples have zero duration")
        }

        let ticks = samples.reduce(UInt64(0)) { $0 + UInt64($1.duration) }
        let seconds = Double(ticks) / Double(config.timescale)
        let mediaLength = samples.reduce(Int64(0)) { $0 + Int64($1.size) }
        let lastEnd = samples.map { $0.originOffset + Int64($0.size) }.max() ?? 0

        // The single most valuable check: the server states the true length, and
        // a fragmented MP4's own timeline is exactly the thing that reads back
        // at 2x. If the rebuilt duration disagrees with the stated one, the
        // timescale or the trun parse is wrong.
        if let expected = expectedDurationMs, expected > 0 {
            let ratio = seconds / (Double(expected) / 1_000)
            AppLog.player(String(
                format: "remux[%@]: %d samples, %.1fs rebuilt vs %.1fs stated (ratio %.3f),"
                    + " timescale %u, media %d MB of %d MB",
                label, samples.count, seconds, Double(expected) / 1_000, ratio,
                config.timescale, Int(mediaLength / 1_048_576), Int(originLength / 1_048_576)
            ))
            if ratio < 0.95 || ratio > 1.05 {
                return reject(String(format: "duration off by %.0f%%", (ratio - 1) * 100))
            }
        }

        if lastEnd > originLength {
            return reject("last sample ends at \(lastEnd), past the stream's \(originLength)")
        }
        // stco is 32-bit. Nothing here approaches 4 GiB, but a silently truncated
        // offset would send the player to the wrong bytes.
        if mediaLength > Int64(UInt32.max) {
            return reject("media \(mediaLength) B exceeds 32-bit chunk offsets (needs co64)")
        }
        return true
    }

    private static func ftyp() -> Data {
        var payload = Data()
        payload.append(contentsOf: Array("isom".utf8))
        payload.append(MP4Box.u32(512))
        for brand in ["isom", "iso2", "avc1", "mp41"] {
            payload.append(contentsOf: Array(brand.utf8))
        }
        return MP4Box.box("ftyp", payload)
    }

    private static func mvhd(timescale: UInt32, duration: UInt64) -> Data {
        var payload = Data()
        payload.append(MP4Box.u32(0))               // creation
        payload.append(MP4Box.u32(0))               // modification
        payload.append(MP4Box.u32(timescale))
        payload.append(MP4Box.u32(UInt32(min(duration, UInt64(UInt32.max)))))
        payload.append(MP4Box.u32(0x0001_0000))     // rate 1.0
        payload.append(MP4Box.u16(0x0100))          // volume 1.0
        payload.append(MP4Box.u16(0))               // reserved
        payload.append(Data(repeating: 0, count: 8))
        for value in [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] {
            payload.append(MP4Box.u32(UInt32(value)))
        }
        payload.append(Data(repeating: 0, count: 24))
        payload.append(MP4Box.u32(2))               // next track ID
        return MP4Box.fullBox("mvhd", version: 0, flags: 0, payload)
    }

    private static func trak(
        config: TrackConfig,
        samples: [Sample],
        duration: UInt64,
        mdatStart: Int64
    ) -> Data {
        var body = Data()
        body.append(tkhd(config: config, duration: duration))
        body.append(MP4Box.box("mdia", mdia(
            config: config, samples: samples, duration: duration, mdatStart: mdatStart
        )))
        return MP4Box.box("trak", body)
    }

    private static func tkhd(config: TrackConfig, duration: UInt64) -> Data {
        var payload = Data()
        payload.append(MP4Box.u32(0))
        payload.append(MP4Box.u32(0))
        payload.append(MP4Box.u32(config.trackID))
        payload.append(MP4Box.u32(0))
        payload.append(MP4Box.u32(UInt32(min(duration, UInt64(UInt32.max)))))
        payload.append(Data(repeating: 0, count: 8))
        payload.append(MP4Box.u16(0))               // layer
        payload.append(MP4Box.u16(0))               // alternate group
        payload.append(MP4Box.u16(config.handler == "soun" ? 0x0100 : 0))
        payload.append(MP4Box.u16(0))
        for value in [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] {
            payload.append(MP4Box.u32(UInt32(value)))
        }
        payload.append(MP4Box.u32(config.width << 16))
        payload.append(MP4Box.u32(config.height << 16))
        // enabled | in movie | in preview
        return MP4Box.fullBox("tkhd", version: 0, flags: 0x7, payload)
    }

    private static func mdia(
        config: TrackConfig,
        samples: [Sample],
        duration: UInt64,
        mdatStart: Int64
    ) -> Data {
        var body = Data()
        var mdhdPayload = Data()
        mdhdPayload.append(MP4Box.u32(0))
        mdhdPayload.append(MP4Box.u32(0))
        mdhdPayload.append(MP4Box.u32(config.timescale))
        mdhdPayload.append(MP4Box.u32(UInt32(min(duration, UInt64(UInt32.max)))))
        mdhdPayload.append(MP4Box.u16(0x55C4))      // language: und
        mdhdPayload.append(MP4Box.u16(0))
        body.append(MP4Box.fullBox("mdhd", version: 0, flags: 0, mdhdPayload))

        var hdlrPayload = Data()
        hdlrPayload.append(MP4Box.u32(0))
        hdlrPayload.append(contentsOf: Array(config.handler.utf8))
        hdlrPayload.append(Data(repeating: 0, count: 12))
        hdlrPayload.append(0)
        body.append(MP4Box.fullBox("hdlr", version: 0, flags: 0, hdlrPayload))

        body.append(MP4Box.box("minf", minf(
            config: config, samples: samples, mdatStart: mdatStart
        )))
        return body
    }

    private static func minf(
        config: TrackConfig,
        samples: [Sample],
        mdatStart: Int64
    ) -> Data {
        var body = Data()
        if config.handler == "soun" {
            body.append(MP4Box.fullBox("smhd", version: 0, flags: 0, Data(repeating: 0, count: 4)))
        } else {
            body.append(MP4Box.fullBox("vmhd", version: 0, flags: 1, Data(repeating: 0, count: 8)))
        }
        var dref = Data()
        dref.append(MP4Box.u32(1))
        dref.append(MP4Box.fullBox("url ", version: 0, flags: 1, Data()))
        var dinf = Data()
        dinf.append(MP4Box.fullBox("dref", version: 0, flags: 0, dref))
        body.append(MP4Box.box("dinf", dinf))
        body.append(MP4Box.box("stbl", stbl(
            config: config, samples: samples, mdatStart: mdatStart
        )))
        return body
    }

    /// The sample table: the whole reason this file exists.
    private static func stbl(
        config: TrackConfig,
        samples: [Sample],
        mdatStart: Int64
    ) -> Data {
        var body = Data()
        body.append(config.sampleDescription)

        // stts, run-length encoded by duration.
        var sttsEntries = Data()
        var sttsCount: UInt32 = 0
        var runCount: UInt32 = 0
        var runDuration: UInt32 = samples[0].duration
        for sample in samples {
            if sample.duration == runDuration {
                runCount += 1
            } else {
                sttsEntries.append(MP4Box.u32(runCount))
                sttsEntries.append(MP4Box.u32(runDuration))
                sttsCount += 1
                runCount = 1
                runDuration = sample.duration
            }
        }
        sttsEntries.append(MP4Box.u32(runCount))
        sttsEntries.append(MP4Box.u32(runDuration))
        sttsCount += 1
        var stts = MP4Box.u32(sttsCount)
        stts.append(sttsEntries)
        body.append(MP4Box.fullBox("stts", version: 0, flags: 0, stts))

        // ctts: presentation offsets, run-length encoded like stts. Omitted
        // entirely when every offset is zero, which is the normal case for audio
        // and for video without B-frames.
        if samples.contains(where: { $0.compositionOffset != 0 }) {
            var cttsEntries = Data()
            var cttsCount: UInt32 = 0
            var runLength: UInt32 = 0
            var runOffset = samples[0].compositionOffset
            for sample in samples {
                if sample.compositionOffset == runOffset {
                    runLength += 1
                } else {
                    cttsEntries.append(MP4Box.u32(runLength))
                    cttsEntries.append(MP4Box.u32(UInt32(bitPattern: runOffset)))
                    cttsCount += 1
                    runLength = 1
                    runOffset = sample.compositionOffset
                }
            }
            cttsEntries.append(MP4Box.u32(runLength))
            cttsEntries.append(MP4Box.u32(UInt32(bitPattern: runOffset)))
            cttsCount += 1
            var ctts = MP4Box.u32(cttsCount)
            ctts.append(cttsEntries)
            // Version 1 so negative offsets are legal; version 0 is unsigned and
            // would reinterpret them as enormous positives.
            let anyNegative = samples.contains { $0.compositionOffset < 0 }
            body.append(MP4Box.fullBox(
                "ctts", version: anyNegative ? 1 : 0, flags: 0, ctts
            ))
            AppLog.player("remux: ctts with \(cttsCount) runs (B-frames present)")
        }

        // stsz: one size per sample.
        var stsz = MP4Box.u32(0)
        stsz.append(MP4Box.u32(UInt32(samples.count)))
        for sample in samples {
            stsz.append(MP4Box.u32(sample.size))
        }
        body.append(MP4Box.fullBox("stsz", version: 0, flags: 0, stsz))

        // Samples are grouped into chunks at the original fragment boundaries.
        //
        // One sample per chunk was simpler and was wrong: 44,003 samples meant
        // 44,003 chunks, a 176 KB `stco`, and AVFoundation issuing a fresh
        // ranged request every few hundred KB — which played, but jittered.
        // Grouping restores the layout a normal MP4 has, so the player reads in
        // long runs. Chunk boundaries fall where the source fragments do, which
        // is exactly where the bytes stop being contiguous.
        var chunkStarts: [Int] = []
        var chunkSampleCounts: [Int] = []
        var previousEnd: Int64 = -1
        for (index, sample) in samples.enumerated() {
            if sample.originOffset != previousEnd {
                chunkStarts.append(index)
                chunkSampleCounts.append(1)
            } else {
                chunkSampleCounts[chunkSampleCounts.count - 1] += 1
            }
            previousEnd = sample.originOffset + Int64(sample.size)
        }

        // stsc, run-length encoded: consecutive chunks holding the same number
        // of samples collapse into one entry.
        var stscEntries = Data()
        var stscCount: UInt32 = 0
        var runStart = 0
        for index in 0..<chunkSampleCounts.count {
            let isLast = index == chunkSampleCounts.count - 1
            let changes = isLast || chunkSampleCounts[index + 1] != chunkSampleCounts[index]
            if changes {
                stscEntries.append(MP4Box.u32(UInt32(runStart + 1)))
                stscEntries.append(MP4Box.u32(UInt32(chunkSampleCounts[index])))
                stscEntries.append(MP4Box.u32(1))
                stscCount += 1
                runStart = index + 1
            }
        }
        var stsc = MP4Box.u32(stscCount)
        stsc.append(stscEntries)
        body.append(MP4Box.fullBox("stsc", version: 0, flags: 0, stsc))

        // stco: one absolute offset per chunk, within THIS file — hence the
        // two-pass build, since the header's own length shifts them.
        var offsets = Data()
        var cursor = mdatStart
        var sampleIndex = 0
        for count in chunkSampleCounts {
            offsets.append(MP4Box.u32(UInt32(truncatingIfNeeded: cursor)))
            for _ in 0..<count {
                cursor += Int64(samples[sampleIndex].size)
                sampleIndex += 1
            }
        }
        var stco = MP4Box.u32(UInt32(chunkSampleCounts.count))
        stco.append(offsets)
        body.append(MP4Box.fullBox("stco", version: 0, flags: 0, stco))
        AppLog.player(
            "remux: \(samples.count) samples in \(chunkSampleCounts.count) chunks,"
                + " \(stscCount) stsc runs"
        )

        // stss: sync samples. Audio is all-sync and omits the box entirely.
        if config.handler != "soun" {
            var syncs = Data()
            var syncCount: UInt32 = 0
            for (index, sample) in samples.enumerated() where sample.isSync {
                syncs.append(MP4Box.u32(UInt32(index + 1)))
                syncCount += 1
            }
            if syncCount > 0, syncCount < UInt32(samples.count) {
                var stss = MP4Box.u32(syncCount)
                stss.append(syncs)
                body.append(MP4Box.fullBox("stss", version: 0, flags: 0, stss))
                let gop = samples.count / max(Int(syncCount), 1)
                AppLog.player(
                    "remux: stss \(syncCount) sync of \(samples.count)"
                        + " samples, GOP ~\(gop)"
                )
            } else {
                // Omitting stss declares every sample a sync sample. For video
                // that is almost never true, and it fails only on an exact seek,
                // which lands mid-GOP on a frame the decoder cannot start from
                // and then starves with no error. Worth shouting about.
                AppLog.player(
                    "remux: WARNING no stss for video —"
                        + " \(syncCount) sync of \(samples.count) samples;"
                        + " exact seeks will land mid-GOP"
                )
            }
        }
        return body
    }
}
#endif
