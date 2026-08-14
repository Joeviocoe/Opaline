import Foundation

// MARK: - Rolling buffer
//
// SABR delivers each stream in order, so a stream is held as one contiguous
// run of bytes plus its starting offset — not as a list of the parts it
// arrived in. A single 10MB response carries ~500 MEDIA parts, and keeping
// them separately turned every append and every read into a linear scan over
// hundreds of entries; the session spent so long re-scanning that it stopped
// answering the player entirely.

extension Data {
    /// `count`-relative slice.
    ///
    /// `Data` does not have to be indexed from zero — `removeFirst` moves
    /// `startIndex` — so subranges must be built off `startIndex` rather than
    /// off 0. Getting this wrong traps once the buffer starts being trimmed.
    func slice(from offset: Int, length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= count else {
            return nil
        }
        let base = startIndex + offset
        // A slice shares storage instead of copying — a 3MB video segment
        // copied per request is both the memory spikes and a chunk of the CPU.
        return self[base..<(base + length)]
    }
}

/// One stream's contiguous bytes and where they start in the file.
struct StreamBuffer {
    var start: Int64
    var data: Data

    var end: Int64 { start + Int64(data.count) }
}

extension SABRSession {
    /// Files the segment: init segments are kept whole and forever (AVPlayer
    /// re-reads them), media is appended to the contiguous run.
    func store(_ segment: SABRSegment) {
        guard !segment.isInit else {
            // A copy on purpose: a slice would keep the whole response alive
            // for as long as the session runs, to save a few kilobytes.
            initSegments[segment.itag] = Data(segment.data)
            return
        }
        guard var buffer = buffers[segment.itag] else {
            buffers[segment.itag] = StreamBuffer(start: segment.start, data: segment.data)
            return
        }
        if segment.start == buffer.end {
            buffer.data.append(segment.data)
        } else if segment.start > buffer.end || segment.start < buffer.start {
            // A gap or a jump backwards: the old run can no longer be extended,
            // so start a new one here.
            buffer = StreamBuffer(start: segment.start, data: segment.data)
        } else {
            // Overlap — the server resent bytes we already hold.
            let skip = Int(buffer.end - segment.start)
            if skip < segment.data.count {
                buffer.data.append(segment.data.dropFirst(skip))
            }
        }
        buffers[segment.itag] = buffer
        trim()
    }

    /// Bytes `offset..<offset+length`, or nil when the stream has not reached
    /// them. Init segments answer from their own store.
    func buffered(itag: Int, offset: Int64, length: Int) -> Data? {
        if let head = initSegments[itag], offset + Int64(length) <= Int64(head.count) {
            return head.slice(from: Int(offset), length: length)
        }
        guard let buffer = buffers[itag],
              offset >= buffer.start,
              offset + Int64(length) <= buffer.end else {
            return nil
        }
        return buffer.data.slice(from: Int(offset - buffer.start), length: length)
    }

    /// Records how far a stream has been handed out. Kept separate from
    /// `buffered` on purpose: that one is called from inside `removeAll`, and
    /// mutating the session from there trips exclusive-access enforcement.
    func markRead(itag: Int, offset: Int64, length: Int) {
        readOffsets[itag] = max(readOffsets[itag] ?? 0, offset + Int64(length))
    }

    /// How many bytes are already held contiguously from `offset` — the write
    /// position for the next chunk of a segment split across parts.
    func bufferedLength(itag: Int, from offset: Int64) -> Int64 {
        guard let buffer = buffers[itag], offset >= buffer.start, offset <= buffer.end else {
            return 0
        }
        return buffer.end - offset
    }

    /// A read is a seek when it lands before what the session still holds.
    func needsSeek(itag: Int, offset: Int64) -> Bool {
        guard let buffer = buffers[itag] else {
            return false
        }
        return offset < buffer.start
    }

    func resetBuffers() {
        buffers.removeAll()
        readOffsets.removeAll()
    }

    func advance(itag: Int, sequence: Int, bufferedMs: Int) {
        let format = itag == audio.itag ? audio : video
        let known = progress[itag]
        progress[itag] = SABRStreamProgress(
            format: format,
            lastSequence: max(known?.lastSequence ?? 0, sequence),
            bufferedMs: max(known?.bufferedMs ?? 0, bufferedMs)
        )
    }

    func setPlaybackCookie(_ cookie: Data) {
        playbackCookie = cookie
    }

    func markEnded() {
        reachedEnd = true
    }

    /// Drops bytes the player has already read, and only falls back to the
    /// ceiling when it has not read anything yet.
    ///
    /// Trimming copies what remains, so it happens rarely and in large steps
    /// rather than shaving a little off every append.
    private func trim() {
        for (itag, var buffer) in buffers {
            let consumed = (readOffsets[itag] ?? buffer.start) - Int64(Self.keepBehind)
            let drop = Int(min(consumed - buffer.start, Int64(buffer.data.count)))
            guard drop > Int(Self.keepBehind) else {
                continue
            }
            buffer.data.removeFirst(drop)
            buffer.start += Int64(drop)
            buffers[itag] = buffer
        }
        var total = buffers.values.reduce(0) { $0 + $1.data.count }
        // Nothing consumed yet and still over the ceiling: take it off the
        // largest stream, since video outweighs audio by an order of magnitude
        // and dropping the whole audio run would read as a backwards seek.
        while total > Self.bufferLimit {
            guard let itag = buffers.max(by: { $0.value.data.count < $1.value.data.count })?.key,
                  var buffer = buffers[itag], !buffer.data.isEmpty else {
                return
            }
            let drop = min(total - Self.bufferLimit, buffer.data.count)
            buffer.data.removeFirst(drop)
            buffer.start += Int64(drop)
            buffers[itag] = buffer
            total -= drop
        }
    }
}
